// HOMEDESK: 保存请求的截止时间判定保持纯函数，便于验证迟到任务不会执行。
use std::{sync::{atomic::{AtomicU8, Ordering}, mpsc::{SyncSender, TrySendError}}, time::Instant};

#[derive(Debug, Eq, PartialEq)]
pub enum EnqueueError { Busy, Stopped }

pub fn try_enqueue<T>(sender: &SyncSender<T>, task: T) -> Result<(), EnqueueError> {
    sender.try_send(task).map_err(|error| match error {
        TrySendError::Full(_) => EnqueueError::Busy,
        TrySendError::Disconnected(_) => EnqueueError::Stopped,
    })
}

pub fn save_request_may_execute(abandoned: bool, now: Instant, deadline: Instant) -> bool {
    !abandoned && now < deadline
}

pub fn claim_queued_save(state: &AtomicU8) -> bool {
    state.compare_exchange(0, 1, Ordering::SeqCst, Ordering::SeqCst).is_ok()
}

pub fn abandon_queued_save(state: &AtomicU8) -> bool {
    state.compare_exchange(0, 2, Ordering::SeqCst, Ordering::SeqCst).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn abandoned_or_expired_save_never_executes() {
        let now = Instant::now();
        assert!(save_request_may_execute(false, now, now + Duration::from_secs(1)));
        assert!(!save_request_may_execute(true, now, now + Duration::from_secs(1)));
        assert!(!save_request_may_execute(false, now, now));
        assert!(!save_request_may_execute(false, now, now - Duration::from_millis(1)));
    }

    #[test]
    fn busy_queue_rejects_instead_of_waiting() {
        let (sender, receiver) = std::sync::mpsc::sync_channel(1);
        try_enqueue(&sender, 1).unwrap();
        assert_eq!(try_enqueue(&sender, 2), Err(EnqueueError::Busy));
        assert_eq!(receiver.recv().unwrap(), 1);
        drop(receiver);
        assert_eq!(try_enqueue(&sender, 3), Err(EnqueueError::Stopped));
    }

    #[test]
    fn claim_and_abandon_are_mutually_exclusive() {
        let claimed = AtomicU8::new(0);
        assert!(claim_queued_save(&claimed));
        assert!(!abandon_queued_save(&claimed));
        let abandoned = AtomicU8::new(0);
        assert!(abandon_queued_save(&abandoned));
        assert!(!claim_queued_save(&abandoned));
    }
}
