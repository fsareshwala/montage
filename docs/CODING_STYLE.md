# Montage — Swift Coding Style Guide

This document defines the coding style conventions for the Montage codebase. All production code
(`Montage/`, `ShareExtension/`, `Shared/`) and test code (`TestSupport/`, `MontageTests/`,
`MontageUITests/`) must follow these rules.

---

## 1. Mandatory Control Flow & Readability Rules

These rules are strictly enforced across the entire codebase, including AI-assisted edits.

### 1.1 Explicit `return` for Boolean Returns

When returning a `Bool` from a function, method, or computed property, never rely on Swift's
implicit single-expression return. Always write the explicit `return` keyword.

**Do:**

```swift
private var isCompleted: Bool {
  return mergePhase == .completed
}

nonisolated static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
  return lhs.id == rhs.id
}
```

**Don't:**

```swift
private var isCompleted: Bool {
  mergePhase == .completed
}

nonisolated static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
  lhs.id == rhs.id
}
```

### 1.2 Avoid `!` When Returning a Boolean

When returning a `Bool`, do not use the logical NOT (`!`) modifier. Instead, write an explicit
`if` / `else` returning `true` and `false` (each on its own line).

**Do:**

```swift
var isEmptySelection: Bool {
  if hasSelectedClips {
    return false
  } else {
    return true
  }
}
```

**Don't:**

```swift
var isEmptySelection: Bool {
  return !hasSelectedClips
}
```

Similarly, prefer explicit `if` / `else` returning `true` / `false` over negated boolean return
expressions when it improves clarity:

```swift
private var isMerging: Bool {
  guard let mergePhase else {
    return false
  }

  if mergePhase == .completed {
    return false
  } else {
    return true
  }
}
```

### 1.3 Never Write Single-Line `if` or `guard` Statements

Control-flow statements (`if`, `else`, `guard`, `for`, `while`, `switch`) must never be written on
a single line. Always place the condition/header, body statements, and closing brace on separate
lines.

**Do:**

```swift
if isRunningInPreviews {
  return
}

guard clips.count >= 2 else {
  return
}
```

**Don't:**

```swift
if isRunningInPreviews { return }

guard clips.count >= 2 else { return }
```

### 1.4 Blank Line After Control Structure Closing Braces

Place a single blank line after the closing `}` of any control structure (`if`, `guard`, `for`,
`while`, `repeat`/`while`, `switch`, `do`/`catch`) to visually separate it from the statements
that follow in the same scope.

**Exceptions:**
- Do **not** add a blank line when the very next non-whitespace line is another closing `}`
  (closing nested blocks).
- Do **not** add a blank line before a continuation clause that belongs to the same control
  structure (`else`, `else if`, `catch`, `while` in `repeat`/`while`).

**Do:**

```swift
func configure() {
  if shouldReset {
    resetState()
  }

  for item in items {
    process(item)
    if item.isFinal {
      finalize(item)
    }
  }

  commitChanges()
}
```

**Don't:**

```swift
func configure() {
  if shouldReset {
    resetState()
  }
  for item in items {
    process(item)
    if item.isFinal {
      finalize(item)
    }
  }
  commitChanges()
}
```

This rule also applies inside SwiftUI `@ViewBuilder` closures when an `if` or `switch` block is
followed by another sibling view.

### 1.5 Avoid the Ternary Operator (`? :`)

Avoid the ternary conditional operator (`condition ? trueValue : falseValue`). The `?` and `:`
punctuation reduces readability compared to explicit control flow. Use an `if` / `else` statement
with a local constant/variable (or an explicit `if` / `else` inside a `@ViewBuilder` or helper
function) instead.

> Note: Standard Swift optional syntax (`Type?`, optional chaining `?.`, nil-coalescing `??`,
> `as?`, `try?`) is **not** the ternary operator and remains idiomatic.

**Do:**

```swift
let clipWord: String
if clips.count == 1 {
  clipWord = "clip"
} else {
  clipWord = "clips"
}
```

**Don't:**

```swift
let clipWord = clips.count == 1 ? "clip" : "clips"
```

---

## 2. Formatting & Layout

- **Indentation:** 2 spaces (no tabs).
- **Braces:** K&R style—opening `{` on the same line separated by a single space. When a
  declaration or condition wraps across multiple lines, place the opening `{` consistently with
  standard Swift formatting (`swift-format`).
- **Line Length:** Aim to wrap lines around 100 characters for readability.
- **Semicolons:** Never use trailing semicolons.
- **Trailing Commas:** Use trailing commas in multi-line array and dictionary literals.
- **Blank Lines:** Use a single blank line to separate logical groups of statements, properties,
  methods, and `// MARK:` sections. Avoid consecutive blank lines.

---

## 3. Imports & File Organization

- **Imports:** Sort `import` statements alphabetically at the top of each file. In test files,
  place `@testable import Montage` after system framework imports, separated by a blank line.
- **Section Markers:** Use `// MARK: - Section Name` in longer files to separate stored
  properties, lifecycle/public API, view sections, and private helpers.
- **Private Helpers & Previews:** Place `private` helper views/types at the bottom of the file,
  followed by `#Preview` blocks in SwiftUI view files.
- **Static Namespaces:** Group stateless static utilities or key constants inside caseless `enum`
  types (e.g., `DurationFormatter`, `TestVideoFixtureFactory`, `private enum Keys`) so they cannot
  be instantiated.

---

## 4. Naming & Types

- **Casing:** `UpperCamelCase` for types, protocols, and actors; `lowerCamelCase` for properties,
  methods, parameters, local variables, and enum cases.
- **Value Types First:** Prefer `struct` and `enum` over `class`. Mark classes `final` unless
  inheritance is explicitly required.
- **Boolean Naming:** Name boolean properties and predicates so they read naturally as assertions
  (e.g., `isMerging`, `isCompleted`, `allowsPhotoAccess`, `hasAnyAudio`, `autoTrimEnabled`).
- **Access Control:** Default to `private` for internal helpers and subviews. Expose `internal` or
  `public` symbols only when shared across files or targets.

---

## 5. Concurrency & Compatibility

- **Actor Isolation:** The project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and
  `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Mark non-UI models and processing types `nonisolated`
  and `Sendable` as appropriate (e.g., `VideoMergeEngine`, `ClipItem`, `MergeConfiguration`).
- **Async/Await:** Prefer structured Swift Concurrency (`async`/`await`) over nested completion
  handlers. Bridge legacy callback APIs cleanly with `withCheckedContinuation` or
  `withCheckedThrowingContinuation`.
- **Availability Checks:** Keep `#available(...)` branches isolated inside
  `Shared/UICompatibility.swift` and `Shared/MediaCompatibility.swift` rather than scattering
  availability checks across feature views and engine code.

---

## 6. Comments & Documentation

- Use `///` doc comments for types, shared models, and non-trivial methods.
- Use `//` comments to document *why* something is done (iOS Share Extension limits, PhotoKit
  quirks, audio crossfade invariants), not to narrate obvious code.

---

## 7. Testing Conventions

- **Unit Tests (`MontageTests`):** Use Swift Testing (`import Testing`, `@Suite`, `@Test`,
  `#expect`, `#require`).
- **UI Tests (`MontageUITests`):** Use `XCTest` (`@MainActor final class ...: XCTestCase`).
- **Cleanup:** Always clean up temporary files and directories created during tests using `defer`.
