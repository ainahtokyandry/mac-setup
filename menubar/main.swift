// MacBar — one menu bar item for tools that would otherwise have one each.
//
// This repository holds only the host: the status item, the dropdown, and the
// contract in Support.swift that a section conforms to. The sections themselves
// live in their own repositories and are compiled in by build.sh, which writes
// the `sections` list this reads:
//
//   storage-bar    free space on the boot volume
//   claude-usage   the three Claude usage limits
//   job-search     the scheduled search's next run
//
// So nothing here knows what is being measured, and updating a section means
// pulling its repository — not editing this one.
//
// No third-party dependencies — plain AppKit, built with swiftc.

import AppKit

Host.run(sections: sections)
