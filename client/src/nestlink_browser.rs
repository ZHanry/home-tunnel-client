//! Browser media reuses the current native capture/input backend and foreground account.
//! The private transport cannot enable capture or input without a signed, live host grant.

#[cfg(any(windows, target_os = "linux"))]
mod desktop {
    use hbb_common::{anyhow::anyhow, bail, base64::{engine::general_purpose::STANDARD, Engine as _}, config::Config,
        lazy_static::lazy_static, password_security, ResultType};
    use enigo::{Enigo, Key, KeyboardControllable, MouseButton, MouseControllable};
    use scrap::{Capturer, Display, Frame, Pixfmt, TraitCapturer, TraitPixelBuffer};
    use serde_derive::Deserialize;
    use std::{collections::BTreeMap, sync::mpsc::{self, SyncSender}, time::{Duration, Instant}};

    enum Command { Allow(String, String), Frame, Input(String), Stop }
    struct Request { command: Command, reply: SyncSender<String> }
    lazy_static! {
        static ref WORKER: Option<SyncSender<Request>> = {
            let (sender, receiver) = mpsc::sync_channel::<Request>(16);
            match std::thread::Builder::new().name("nestlink-browser-capture".into()).spawn(move || {
                let mut state = State::new();
                loop {
                    match receiver.recv_timeout(Duration::from_millis(250)) {
                        Ok(request) => {
                            let result = state.handle(request.command).unwrap_or_else(|error| {
                                state.reset(); serde_json::json!({"error": error.to_string()}).to_string()
                            });
                            let _ = request.reply.try_send(result);
                        }
                        Err(mpsc::RecvTimeoutError::Timeout) => {},
                        Err(mpsc::RecvTimeoutError::Disconnected) => { state.reset(); return; },
                    }
                    if state.epoch != 0 && (!state.live() || state.heartbeat.elapsed() > Duration::from_secs(3)) { state.release(); }
                    if state.epoch != 0 && !state.live() { state.reset(); }
                }
            }) {
                Ok(_) => Some(sender),
                Err(error) => { hbb_common::log::error!("Browser capture worker unavailable: {error}"); None }
            }
        };
    }
    pub fn call(kind: &str, id: String, payload: String) -> String {
        let Some(worker) = WORKER.as_ref() else { return serde_json::json!({"error":"Capture unavailable"}).to_string(); };
        let (reply, answer) = mpsc::sync_channel(1);
        let command = match kind { "allow" => Command::Allow(id, payload), "frame" => Command::Frame,
            "input" => Command::Input(payload), _ => Command::Stop };
        if worker.try_send(Request { command, reply }).is_err() { return serde_json::json!({"error":"Capture busy"}).to_string(); }
        answer.recv_timeout(Duration::from_secs(2)).unwrap_or_else(|_| serde_json::json!({"error":"Capture timeout"}).to_string())
    }
    pub fn check_password(candidate: &str) -> bool {
        use hbb_common::{config::{decode_permanent_password_h1_from_storage, decode_preset_password_h1_from_storage},
            sha2::{Digest, Sha256}, sodiumoxide::utils::memcmp};
        if !crate::nestlink_auth::ready() || candidate.is_empty() || candidate.len() > 512 ||
            password_security::approve_mode() == password_security::ApproveMode::Click { return false; }
        if password_security::temporary_enabled() && memcmp(candidate.as_bytes(), password_security::temporary_password().as_bytes()) { return true; }
        if !password_security::permanent_enabled() { return false; }
        let (local, salt) = Config::get_local_permanent_password_storage_and_salt();
        let (storage, salt, preset) = if local.is_empty() { let (storage, salt) = Config::get_preset_password_storage_and_salt(); (storage, salt, true) }
            else { (local, salt, false) };
        if storage.is_empty() { return false; }
        let hash = if preset { decode_preset_password_h1_from_storage(&storage) } else { decode_permanent_password_h1_from_storage(&storage) };
        if let Some(hash) = hash {
            let mut input = Sha256::new(); input.update(candidate.as_bytes()); input.update(salt.as_bytes());
            memcmp(&hash, &input.finalize())
        } else { memcmp(storage.as_bytes(), candidate.as_bytes()) }
    }
    struct State {
        id: String, epoch: u64, until: Instant, heartbeat: Instant, capturer: Option<Capturer>, enigo: Enigo,
        keys: BTreeMap<String, Key>, buttons: BTreeMap<u8, MouseButton>, width: usize, height: usize,
        origin: (i32, i32), cached: String,
    }
    impl State {
        fn new() -> Self { Self { id:String::new(), epoch:0, until:Instant::now(), heartbeat:Instant::now(), capturer:None,
            enigo:Enigo::new(), keys:BTreeMap::new(), buttons:BTreeMap::new(), width:0, height:0, origin:(0,0), cached:String::new() } }
        fn live(&self) -> bool { self.epoch != 0 && Instant::now() < self.until && crate::nestlink_auth::browser_epoch_live(self.epoch) }
        fn release(&mut self) {
            for (_, key) in std::mem::take(&mut self.keys) { self.enigo.key_up(key); }
            for (_, button) in std::mem::take(&mut self.buttons) { self.enigo.mouse_up(button); }
        }
        fn reset(&mut self) { self.release(); self.id.clear(); self.epoch=0; self.capturer=None; self.cached.clear(); }
        fn handle(&mut self, command: Command) -> ResultType<String> {
            match command {
                Command::Stop => { self.reset(); return Ok(String::new()); },
                Command::Allow(id, grant) => {
                    #[derive(Deserialize)] #[serde(deny_unknown_fields)]
                    struct Authorization { grant: String, offer: String, answer: String }
                    let value: Authorization = serde_json::from_str(&grant)?;
                    let (epoch, remaining) = crate::nestlink_auth::browser_grant(&value.grant, &id, &value.offer, &value.answer)?;
                    if self.id != id { self.reset(); self.id=id; self.heartbeat=Instant::now(); }
                    self.epoch=epoch; self.until=Instant::now()+remaining; return Ok(String::new());
                },
                _ if !self.live() => bail!("远控登录或许可已失效"),
                Command::Input(value) => { self.input(&value)?; return Ok(String::new()); },
                Command::Frame => {},
            }
            if self.capturer.is_none() {
                let display = Display::primary()?; self.width=display.width(); self.height=display.height(); self.origin=display.origin();
                if self.width == 0 || self.height == 0 || self.width > 8192 || self.height > 8192 || self.width*self.height > 32768000 { bail!("屏幕尺寸超出限制"); }
                let mut capturer = Capturer::new(display)?;
                #[cfg(windows)] capturer.set_gdi();
                self.capturer=Some(capturer);
            }
            let capturer = self.capturer.as_mut().ok_or_else(|| anyhow!("捕获不可用"))?;
            let frame = match capturer.frame(Duration::from_millis(0)) {
                Ok(frame) => frame,
                Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => return Ok(self.cached.clone()),
                Err(error) => return Err(error.into()),
            };
            let Frame::PixelBuffer(frame) = frame else { bail!("屏幕捕获格式不支持"); };
            let width=frame.width(); let height=frame.height(); let stride=frame.stride().first().copied().unwrap_or(0);
            if stride < width*4 || frame.data().len() < stride*height || ![Pixfmt::BGRA, Pixfmt::RGBA].contains(&frame.pixfmt()) { bail!("屏幕数据无效"); }
            let mut rgb=Vec::with_capacity(width*height*3);
            for row in 0..height { for col in 0..width {
                let offset=row*stride+col*4; let pixel=&frame.data()[offset..offset+4];
                if frame.pixfmt()==Pixfmt::BGRA { rgb.extend_from_slice(&[pixel[2],pixel[1],pixel[0]]); }
                else { rgb.extend_from_slice(&pixel[..3]); }
            } }
            let rgb=image::RgbImage::from_raw(width as u32,height as u32,rgb).ok_or_else(|| anyhow!("屏幕数据无效"))?;
            let image=if width > 1920 || height > 1080 {
                image::DynamicImage::ImageRgb8(rgb).resize(1920,1080,image::imageops::FilterType::Triangle).to_rgb8()
            } else { rgb };
            let mut bytes=Vec::new(); image::codecs::jpeg::JpegEncoder::new_with_quality(&mut bytes,72)
                .encode(image.as_raw(),image.width(),image.height(),image::ColorType::Rgb8)?;
            if bytes.len()>2097152 { bail!("屏幕帧超出限制"); }
            self.cached=STANDARD.encode(bytes); Ok(self.cached.clone())
        }
        fn input(&mut self, raw: &str) -> ResultType<()> {
            if raw.len()>8192 { bail!("输入超出限制"); }
            #[derive(Deserialize)] struct Input { kind:String, x:Option<f64>, y:Option<f64>, button:Option<u8>, down:Option<bool>, key:Option<String>, text:Option<String> }
            let value:Input=serde_json::from_str(raw)?;
            self.heartbeat=Instant::now();
            match value.kind.as_str() {
                "heartbeat" => {}, "release" => self.release(),
                "move" => {
                    let x=value.x.ok_or_else(|| anyhow!("Missing x"))?; let y=value.y.ok_or_else(|| anyhow!("Missing y"))?;
                    if !x.is_finite() || !y.is_finite() || !(0.0..=1.0).contains(&x) || !(0.0..=1.0).contains(&y) || self.width==0 { bail!("指针位置无效"); }
                    self.enigo.mouse_move_to(self.origin.0+(x*(self.width-1) as f64).round() as i32, self.origin.1+(y*(self.height-1) as f64).round() as i32);
                },
                "button" => {
                    let index=value.button.ok_or_else(|| anyhow!("Missing button"))?;
                    let button=match index { 0=>MouseButton::Left,1=>MouseButton::Middle,2=>MouseButton::Right,_=>bail!("鼠标按钮无效") };
                    if value.down==Some(true) { if !self.buttons.contains_key(&index) { self.enigo.mouse_down(button.clone()).map_err(|error| anyhow!("{error:?}"))?; self.buttons.insert(index,button); } }
                    else { self.enigo.mouse_up(button); self.buttons.remove(&index); }
                },
                "wheel" => {
                    let x=value.x.unwrap_or(0.0);let y=value.y.unwrap_or(0.0);
                    if !x.is_finite()||!y.is_finite()||x.abs()>5.0||y.abs()>5.0 { bail!("滚动值无效"); }
                    self.enigo.mouse_scroll_x(x as i32); self.enigo.mouse_scroll_y(y as i32);
                },
                "key" => {
                    let code=value.key.ok_or_else(|| anyhow!("Missing key"))?;
                    let Some(key)=key(&code) else { return Ok(()); };
                    if value.down==Some(true) { if !self.keys.contains_key(&code) { self.enigo.key_down(key.clone()).map_err(|error| anyhow!("{error:?}"))?; self.keys.insert(code,key); } }
                    else { self.enigo.key_up(key); self.keys.remove(&code); }
                },
                "text" => { let text=value.text.unwrap_or_default(); if text.len()>4096 || text.chars().any(|c| c.is_control()&&!matches!(c,'\n'|'\t')) { bail!("文字输入无效"); } self.enigo.key_sequence(&text); },
                _ => bail!("输入类型无效"),
            }
            Ok(())
        }
    }
    fn key(code: &str) -> Option<Key> {
        Some(match code {
            "ControlLeft"|"ControlRight"=>Key::Control,"ShiftLeft"|"ShiftRight"=>Key::Shift,
            "AltLeft"|"AltRight"=>Key::Alt,"MetaLeft"|"MetaRight"=>Key::Meta,
            "Enter"|"NumpadEnter"=>Key::Return,"Tab"=>Key::Tab,"Space"=>Key::Space,"Backspace"=>Key::Backspace,
            "Escape"=>Key::Escape,"Delete"=>Key::Delete,"Home"=>Key::Home,"End"=>Key::End,"PageUp"=>Key::PageUp,"PageDown"=>Key::PageDown,
            "ArrowLeft"=>Key::LeftArrow,"ArrowRight"=>Key::RightArrow,"ArrowUp"=>Key::UpArrow,"ArrowDown"=>Key::DownArrow,
            "F1"=>Key::F1,"F2"=>Key::F2,"F3"=>Key::F3,"F4"=>Key::F4,"F5"=>Key::F5,"F6"=>Key::F6,
            "F7"=>Key::F7,"F8"=>Key::F8,"F9"=>Key::F9,"F10"=>Key::F10,"F11"=>Key::F11,"F12"=>Key::F12,
            "Comma"=>Key::Layout(','),"Period"=>Key::Layout('.'),"Slash"=>Key::Layout('/'),"Semicolon"=>Key::Layout(';'),"Quote"=>Key::Layout('\''),
            "BracketLeft"=>Key::Layout('['),"BracketRight"=>Key::Layout(']'),"Backslash"=>Key::Layout('\\'),"Backquote"=>Key::Layout('`'),"Minus"=>Key::Layout('-'),"Equal"=>Key::Layout('='),
            _ if code.len()==4&&code.starts_with("Key")=>Key::Layout(code.chars().nth(3)?.to_ascii_lowercase()),
            _ if code.len()==6&&code.starts_with("Digit")=>Key::Layout(code.chars().nth(5)?),
            _ => return None,
        })
    }
}
pub fn call(kind: &str, id: String, payload: String) -> String {
    #[cfg(any(windows, target_os="linux"))] { return desktop::call(kind,id,payload); }
    #[cfg(not(any(windows, target_os="linux")))] { let _=(kind,id,payload); "Browser hosting unavailable".to_owned() }
}
pub fn check_password(password: &str) -> bool {
    #[cfg(any(windows, target_os="linux"))] { return desktop::check_password(password); }
    #[cfg(not(any(windows, target_os="linux")))] { let _=password; false }
}
pub fn stop() { let _ = call("stop",String::new(),String::new()); }
pub fn authorize(id: String, grant: String, offer: String, answer: String) -> String {
    call("allow", id, serde_json::json!({"grant":grant,"offer":offer,"answer":answer}).to_string())
}
