//! The only words a command may report as its current step. Plain phrases chosen here, never text from an engine,
//! so a step can be shown to the user as it is. The parent keeps the same list and ignores anything else.

pub const CHECKING: &str = "Checking the machine";
pub const STOPPING: &str = "Stopping the machine";
pub const BACKING_UP: &str = "Backing up (this can take several minutes for big disks)";
pub const DELETING: &str = "Deleting";
pub const CREATING: &str = "Creating the machine";
pub const DONE: &str = "Done";
