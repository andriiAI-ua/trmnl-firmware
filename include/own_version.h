#ifndef OWN_VERSION_H
#define OWN_VERSION_H

// The build number of our fork. The firmware version is "<upstream version>-own.<FW_OWN_BUILD>".
// build.sh increases this number before each release build.
// Do not decrease it: trmnl-server sends a build to a device only when the build is newer.
// An own build is newer than the upstream build with the same upstream version.
#define FW_OWN_BUILD 5

#endif
