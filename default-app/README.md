# default-app

A macOS command-line tool. It shows which app opens a file name, and it sets the default app for many file types in one command.

```console
$ default-app probe md json ./Makefile
md	net.daringfireball.markdown	/Applications/Xcode.app
json	public.json	/Applications/Xcode.app
./Makefile	public.make-source	/Applications/Xcode.app

$ default-app set com.microsoft.VSCode md json ./Makefile
md	net.daringfireball.markdown	/Applications/Xcode.app -> /Applications/Visual Studio Code.app
json	public.json	/Applications/Xcode.app -> /Applications/Visual Studio Code.app
./Makefile	public.make-source	/Applications/Xcode.app -> /Applications/Visual Studio Code.app
```

## Why

On a Mac that has Xcode and a code editor, `.md`, `.json`, `.yaml`, `.py` and C files can open in Xcode. Finder changes the app for one file type at a time (Get Info, Open with, Change All). `default-app` changes a list of file types in one command, and it prints the app that each one had before.

## Install

`default-app` needs macOS 12 or later. The package asks for Swift 5.9 or later. It is built and tested with Swift 6.3.

```sh
git clone https://github.com/junhoyeo/tools.git
cd tools/default-app
swift build -c release
```

The binary is `.build/release/default-app`. Copy it to a directory that is on your `PATH`.

## Commands

### `default-app probe [name ...]`

Prints one line for each name: the name, the content type that macOS gives a file with that name, and the app that opens it. Tabs separate the three fields. A `-` means that macOS has no content type or no app for the name.

`probe` changes nothing.

### `default-app set <app> [name ...]`

Makes `<app>` the default app for the content type of each name. `<app>` is an application path (`/Applications/Visual Studio Code.app`) or a bundle identifier (`com.microsoft.VSCode`).

After each change, `set` asks macOS again and prints the app before and the app after. The exit status is 1 when a name did not get the app.

### Names

| You write | It means |
| --- | --- |
| `md`, `.md`, `c++` | An extension, also when a file or a folder with that name exists. |
| `README.md`, `src/main.rs` | A file name or a path. Only the last part is used. |
| `./Makefile`, `./.gitignore` | A file name with no extension. Write it as a path, because a word with no dot and no slash is an extension. |

`probe` checks a path that exists on disk as it is. The result is then the result for that one item: it includes an app that you chose for that file alone, and an executable file with no extension is `public.unix-executable`. `set` only uses the name.

Without names, both commands read them from a pipe or a file on standard input, one per line. Spaces at the start and at the end of a line are removed. Blank lines and lines that start with `#` are skipped.

## A list of code files

[`code-files.txt`](code-files.txt) is a list of names of source, markup and configuration files. To open all of them in one editor:

```sh
default-app set com.microsoft.VSCode < code-files.txt
```

`default-app probe < code-files.txt` shows the content type and the app that each name has now.

Read the list first, and remove the names that you want to keep in another app. Names can share a content type: `yml` and `yaml` are both `public.yaml`, so remove both to keep either. The top of the file says which names are not in the list, and why.

The list has about 160 content types. On a macOS version that asks you to confirm a change, you answer one dialog for each content type whose app changes.

## What to know

- **macOS keeps the default app for a content type, not for an extension.** `yml` and `yaml` are both `public.yaml`, so a change to one changes the other. `probe` shows the content type.
- **Some code extensions share a content type with other files.** macOS reads `.ts` as an MPEG-2 transport stream, so a video file with that extension gets the same app as a TypeScript file.
- **`set` refuses a name without an extension that macOS does not know.** A file such as `Dockerfile` or `.env` has the content type `public.data`. All such files share that type, so a change for one name would change them all. An unknown extension is different: macOS gives it a content type of its own, and `set` accepts it.
- **There is no command to undo a change.** `NSWorkspace` has no call that removes a choice. You can run `set` again with the app that the output shows on the left of the arrow. That app then becomes a saved choice, also when macOS picked it by itself before. A name that had no app (`-`) cannot go back to none.
- **macOS stores the bundle identifier of the app, not its path.** When two copies of an app are installed, macOS chooses the copy that opens the file. The `set` output shows that copy.
- **macOS can ask you to confirm every change.** macOS 26.7.2 shows a dialog for each content type whose app changes: *Do you want all documents with the extensions “.md” and “.markdown” to open with “TextEdit”, or to keep using “Xcode”?* `set` waits for your answer, and prints a line when it has waited for 2 seconds. The dialog stays open when you stop `default-app`. macOS 26.2 applied the same changes without a dialog. With nobody to answer, as on a CI runner, `set` does not return.

## How it works

For each name, `default-app` creates an empty file with that name in a temporary directory. When the extension belongs only to package types, such as `.xcodeproj`, it creates a directory. It reads the content type of that item, and it asks `NSWorkspace.urlForApplication(toOpen:)` for the app. This is the lookup that Finder uses when you double-click a file. The answer is therefore correct for a file name that has its own content type (`Makefile`), and for two extensions of one content type that open in different apps.

An empty file is enough, because macOS takes the content type of a file from its name. One exception is an executable file with no extension. `probe` only sees that when you give it the path of the real file.

`set` calls `NSWorkspace.setDefaultApplication(at:toOpen:)` with the content type, and then repeats the lookup.

## Related tools

- [duti](https://github.com/moretension/duti)
- [utiluti](https://github.com/scriptingosx/utiluti)
