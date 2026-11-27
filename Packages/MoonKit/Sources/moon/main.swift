import Foundation
import MoonKit

// `moon check <folder>`: loads every module headlessly and reports problems,
// including elements a view gets wrong.
let arguments = CommandLine.arguments.dropFirst()
guard arguments.first == "check", let folder = arguments.dropFirst().first else {
    print("usage: moon check <app folder>")
    exit(2)
}

let workspace = Workspace(folders: Folders(builtin: URL(filePath: folder)))
workspace.reload()

var failed = false
for problem in workspace.problems.values.sorted(by: { $0.file < $1.file }) {
    print("\(problem.file): \(problem.message)")
    failed = true
}
for (name, tree) in workspace.trees.sorted(by: { $0.key < $1.key }) {
    for problem in tree.problems {
        print("\(workspace.file(of: name)): \(problem)")
        failed = true
    }
}
// Placeholders don't fail the check: the mod still works, and each is
// something to add to MoonSwift.
for (file, gaps) in workspace.warnings.sorted(by: { $0.key < $1.key }) {
    for gap in gaps { print("\(file): warning: \(gap)") }
}
if workspace.trees[Workspace.shell] == nil {
    print("no main.luau in \(folder)")
    failed = true
}
if !failed {
    print("ok: \(workspace.trees.count) modules")
}
exit(failed ? 1 : 0)
