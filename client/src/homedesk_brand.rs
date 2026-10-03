// HOMEDESK: Keep the compiled brand default isolated from upstream custom-client overrides.
use std::sync::Once;

static INITIALIZE_BRAND: Once = Once::new();

pub fn init() {
    INITIALIZE_BRAND.call_once(|| {
        let mut app_name = match hbb_common::config::APP_NAME.write() {
            Ok(value) => value,
            Err(poisoned) => poisoned.into_inner(),
        };
        if app_name.as_str() == "RustDesk" {
            *app_name = env!("HOMEDESK_CONFIG_NAMESPACE").to_owned(); // HOMEDESK: 升级保留身份命名空间，显示品牌独立。
        }
    });
}
