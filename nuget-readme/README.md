# ghūl compiler

[![CI/CD](https://img.shields.io/github/actions/workflow/status/ghul-lang/ghul/ci.yml?branch=main)](https://github.com/ghul-lang/ghul/actions?query=workflow%3ACI)
[![NuGet version (ghul.compiler)](https://img.shields.io/nuget/v/ghul.compiler.svg)](https://www.nuget.org/packages/ghul.compiler/)
[![Release](https://img.shields.io/github/v/release/ghul-lang/ghul?label=release)](https://github.com/ghul-lang/ghul/releases)
[![Release Date](https://img.shields.io/github/release-date/ghul-lang/ghul)](https://github.com/ghul-lang/ghul/releases)
[![Issues](https://img.shields.io/github/issues/ghul-lang/ghul)](https://github.com/ghul-lang/ghul/issues) 
[![License](https://img.shields.io/github/license/ghul-lang/ghul)](https://github.com/ghul-lang/ghul/blob/main/LICENSE)
[![Coverage](https://img.shields.io/endpoint?url=https%3A%2F%2Fghul-lang.github.io%2Fghul-coverage-report%2Fbadge.json)](https://ghul-lang.github.io/ghul-coverage-report/)
[![ghūl](https://img.shields.io/badge/gh%C5%ABl-100%25!-information)](https://ghul.dev)

This package contains the [ghūl programming language](https://ghul.dev) [compiler](https://github.com/ghul-lang/ghul) packaged as a [.NET tool](https://docs.microsoft.com/en-us/dotnet/core/tools/global-tools). It is a [self-hosting compiler](https://en.wikipedia.org/wiki/Self-hosting_(compilers)): the compiler itself is written entirely in ghūl.

![ghūl logo icon small](https://raw.githubusercontent.com/ghul-lang/ghul-dev/035cc6d3997514d03cbbd7b15133c37bf2a79f4e/src/.vuepress/public/ghul-logo-icon-128.png)

## Targets

The compiler builds for three targets: .NET 10, WebAssembly and native executables through LLVM.

- **.NET** builds standard assemblies and NuGet packages. The compiler is driven by MSBuild from a `.ghulproj` project file, and needs the [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0), which provides both the runtime the compiler tool runs on and the reference assemblies your projects build against. A ghūl program can use any .NET library. This is the best target for a real project today.
- **WebAssembly** builds a WasmGC module and a JavaScript loader. It runs under Node.js, or in a browser that supports WasmGC. It is built with the `ghul` command-line tool from the [ghul-cli](https://github.com/ghul-lang/ghul-cli) repository, from a `ghul-project.json` manifest, and needs no .NET SDK to build or run on Linux x64 and arm64.
- **Native** builds a statically linked executable for Linux on x64 or arm64, linked with `ghul-llvm`. It is built with `ghul` and needs no .NET SDK or C compiler.

The WebAssembly and native targets use ghūl's own library, [ghul-runtime](https://github.com/ghul-lang/ghul-runtime), in place of the .NET libraries. It is enough to build the compiler itself and to run most of the Rosetta Code solutions, and it doesn't have everything: there are no regular expressions, no HTTP or sockets, no culture-aware formatting, and no `decimal`, and a program can't call a library that already exists. Native programs can call C with `@extern`. See [WebAssembly](https://ghul.dev/webassembly.html) and [native executables](https://ghul.dev/native.html) for what each supports.

## Prerequisites

For the .NET target, the [.NET 10 SDK](https://dotnet.microsoft.com/en-us/download/dotnet/10.0). For the other two, only the `ghul` command, which installs as a native executable on Linux x64 and arm64 and as a .NET tool anywhere else, and Node.js to run WebAssembly programs (`ghul install node` fetches one).

## Getting the compiler

There are a few different ways to get the compiler - you might not need to use this package directly.

### Use a ghūl .NET project template

If you initialize your project using one of the [ghūl .NET project templates](https://www.nuget.org/packages/ghul.templates/), the template will add the compiler to your project folder as a local .NET tool - just run `dotnet tool restore` to restore it. 

### Clone the ghūl GitHub repository template

If you create a new GitHub repo from the [ghūl repository template](https://github.com/ghul-lang/ghul-repository-template), then the compiler will be pre-configured as a local .NET tool in your project folder - run `dotnet tool restore` to restore it.

### Use the ghūl development container image

The compiler is pre-installed globally in the [ghūl development container](https://github.com/users/degory/packages/container/package/ghul%2Fdevcontainer)

### Install the compiler as a local or global .NET tool

If none of the above options suits, you can manually install the compiler from this package - see below for details.

## Using the compiler

### Project file

The compiler expects to be driven by MSBuild using a `.ghulproj` project file.
See the [ghūl test](https://github.com/ghul-lang/ghul-test) project for
a real-world example, or use one of the project templates to get started.

### Source files

You'll need some ghūl source files. By convention ghūl source files have the extension `.ghul`, and the standard MSBuild targets will include `**/*.ghul` when building.

### Building and running

Once you have a project file and some ghūl source files, you can use the normal
.NET SDK commands to build, pack, and run your project:

```sh
dotnet build
```

```sh
dotnet pack
```

```sh
dotnet run
```

### Runtime dependencies for ghūl applications

Applications written in ghūl require the [.NET 10 runtime](https://dotnet.microsoft.com/download/dotnet/10.0).

## Development environment

### Visual Studio Code

[Visual Studio Code](https://code.visualstudio.com) will give you rich language support via the [ghūl VSCode language extension](https://marketplace.visualstudio.com/items?itemName=degory.ghul).

### Dev container

Any container image with the .NET 10 SDK will do. Pin `ghul.compiler` in your project's local .NET tool manifest and the compiler will be restored automatically when the container starts. A minimal worked example is in [this gist](https://gist.github.com/degory/1d6894fe1cf0bf73bb75cbf9c9176a0a).

## Basic ghūl language tutorial

For a short ghūl programming language tutorial and reference, see [GHUL.md](https://github.com/ghul-lang/ghul/blob/main/GHUL.md). For more ghūl language details, see the [the ghūl programming language website](https://ghul.dev)

## Manual compiler install

### Local tool install
To install the compiler locally in your project folder:

```sh
dotnet new tool-manifest # if you don't already have a tool manifest file
```
```sh
dotnet tool install ghul.compiler # install the latest release of the compiler locally
```
```sh
dotnet ghul-compiler # run the compiler
```

A local tool install means you get a predictable compiler version on every build, provided you check in the tool manifest. It also means you can easily use different versions of the compiler for different projects on the same machine. 

### Global tool install

To install the compiler globally for the current user:

```sh
dotnet tool install --global ghul.compiler # install the latest release of the compiler globally
```
```sh
ghul-compiler # run the compiler
```

## Gotchas

The ghūl language is sufficiently expressive and the compiler is stable enough for the compiler itself to be written in ghūl. Like any compiler it has [bugs](https://github.com/ghul-lang/ghul/issues?q=is%3Aissue+is%3Aopen+label%3Abug) - issue reports are welcome.

## Contributing

Bug reports, language questions, documentation fixes and code are all welcome. See [CONTRIBUTING.md](https://github.com/ghul-lang/ghul/blob/main/CONTRIBUTING.md) for how to build and test the compiler and how to raise a pull request, and [SECURITY.md](https://github.com/ghul-lang/ghul/blob/main/SECURITY.md) for how to report a suspected vulnerability.
