pub mod box_manager;
pub mod remote_view;
pub mod channels_view;
pub mod timers_view;
pub mod sync_view;
pub mod bootlogo_view;
pub mod image_view;
pub mod support_view;

pub use box_manager::BoxManagerView;
pub use remote_view::RemoteView;
pub use channels_view::ChannelsView;
pub use timers_view::TimersView;
pub use sync_view::SettingsSyncView;
pub use bootlogo_view::BootlogoView;
pub use image_view::ImageView;
pub use support_view::SupportView;
