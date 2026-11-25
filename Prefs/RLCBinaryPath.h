#import <Foundation/Foundation.h>
#import <roothide.h>

// Absolute path to a jailbreak-provided binary.
//
// jbroot() already handles all three layouts - rootful (identity), rootless
// (/var/jb prefix) and roothide (a randomly named directory) - so the caller only
// needs to say which binary it wants.
//
// The packaged path is the jbroot location: "/usr/bin/killall" lives under the
// bootstrap on rootless and roothide, and next to nothing on rootful where the
// prefix is the empty string.
static inline NSString *RLCBinaryPath(NSString *path) {
    return jbroot(path);
}
