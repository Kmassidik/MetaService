# Control plane for x86_64 (Intel and AMD): not started

The control plane for Apple Silicon is in `../arm64/` (Swift, built and tested). This folder is where the one for x86_64 machines will go when we need it.
Same job and same API as the arm64 one (`../../contract/`), the same panel (`../../frontend/`). The language is not chosen yet.
Linux and Windows on x86_64 would be decided here too: only the CPU names a folder, so whatever we build for x86_64 starts in this folder.
