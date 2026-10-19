# drop: qt6
# VulkanCapsViewer is built with qmake6, and qt6 needs mesa, which needs
# vulkan-sdk (libplacebo -> vulkan-sdk closes the loop through ffmpeg).
# First build without the caps viewer; pass 2 builds vulkan-sdk as Pat's.
/^echo "Building VulkanCapsViewer-/,/^cp -a gfx\/android_icon_256\.png /d
