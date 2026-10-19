# Vulkan-Profiles' "vkprofiles min-api-version" step (VpGenerate-Profiles)
# reads the Khronos profile schemas (profiles-*.json) from
# external/Khronos-Schemas/vulkan under the source dir; when that is missing
# it downloads them from api.github.com into $TMP.  Clone the repository
# there first: sfs-build.sh sends https://github.com/... to the mirror in
# seeds/git, so this works offline and gives the files Pat's build fetched.
/^cd \$TMP\/Vulkan-Profiles-vulkan-sdk-\$VULKAN_PROFILES_VERSION$/a\
git clone -q https://github.com/KhronosGroup/Khronos-Schemas.git external/Khronos-Schemas || exit 1
