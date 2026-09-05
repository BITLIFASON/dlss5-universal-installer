# Safety

- Packages in `packages` are unverified until their source, version, and SHA-256 are recorded.
- The tool does not automatically run third-party `.exe`, `.bat`, or `.cmd` files from archives, except for the explicitly pinned ReShade installer used by Bootstrap.
- A point backup of only the files being replaced is created before changing a game.
- Unknown DLLs are not deleted when a profile is removed.
- Administrator rights are not requested silently; the tool shows a warning first.
- Online games with anti-cheat are outside the scope of this utility.
