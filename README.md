# Medipix

[![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://chenspc.github.io/Medipix.jl/stable)
[![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://chenspc.github.io/Medipix.jl/dev)
[![Build Status](https://github.com/chenspc/Medipix.jl/workflows/CI/badge.svg)](https://github.com/chenspc/Medipix.jl/actions)
[![Build Status](https://ci.appveyor.com/api/projects/status/github/chenspc/Medipix.jl?svg=true)](https://ci.appveyor.com/project/chenspc/Medipix-jl)
[![Coverage](https://codecov.io/gh/chenspc/Medipix.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/chenspc/Medipix.jl)

This is a control software package for Medipix detectors. Testing of the package is carried out on a quad-chip Medipix-4R detector ([Merlin EM](https://quantumdetectors.com/products/merlinem/) by QuantumDetector) installed on [JEM-ARM300F2 GRAND ARM™2](https://www.jeol.co.jp/en/products/detail/JEM-ARM300F2.html) at [Rosalind Franklin Institute](https://www.rfi.ac.uk/about/).

## Installation

* JuilaLang: [Downloads](https://julialang.org/downloads/) and [Documentation](https://docs.julialang.org/)
* Open a Julia REPL, press `]` to use the package mode and add the package. (first time only)

```julia
pkg> add Medipix
```

## Basic usage

Before establishing a connection to the Medipix detector, the Merlin software needs to be opened on the Medipix host PC, i.e. MerlinPC. If running locally on the MerlinPC, a `MedipixConnection` can be set up as below.

```julia
julia> using Medipix

julia> m = MedipixConnection()
MedipixConnection(ip"127.0.0.1", 6341, 6342, Sockets.TCPSocket(Base.Libc.WindowsRawSocket(0x0000000000006dc8) open, 0 bytes waiting), S
ockets.TCPSocket(Base.Libc.WindowsRawSocket(0x0000000000006f48) open, 0 bytes waiting), String[])

```

Remote connection from another computer on the same network can be achieved by supplying the MerlinPC's IP address. Note that only one connection is allowed by the Merlin software. Close any existing connection using the function `close_connection` before attempting a new connection. 

```julia
julia> using Medipix

julia> medipix_ip = ip"172.22.73.9"
ip"172.22.73.9"

julia> m = MedipixConnection(medipix_ip)
MedipixConnection(ip"172.22.73.9", 6341, 6342, Sockets.TCPSocket(RawFD(26) open, 0 bytes waiting), Sockets.TCPSocket(RawFD(27) open, 0 bytes waiting), String[])
```

The `@medipix` macro provides an easy way to add functions that coorespond to the commands implemented via the TCP/IP protocal. For example: 

```julia
julia> @medipix "CMD" "STARTACQUISITION"
cmd_startacquisition (generic function with 1 method)

julia> @medipix "GET" "DETECTORSTATUS"
get_detectorstatus (generic function with 1 method)

julia> @medipix "GET/SET" "ACQUISITIONTIME"
set_acquisitiontime (generic function with 1 method)
```

These functions generate Medipix command strings, which need to be sent via the connection using the `send_cmd` function to either get/set parameters or executing commands.

```julia
julia> cmd = get_acquisitiontime()
"MPX,0000000020,GET,ACQUISITIONTIME"

julia> send_cmd(m, cmd)
"0.412270"

julia> send_cmd(m, cmd; verbose=true)
[2023-05-27T18:31:00.285]       GET,ACQUISITIONTIME >>> --- <<< GET,ACQUISITIONTIME,0.412270,0
"0.412270"

julia> cmds = [set_acquisitiontime(1), get_acquisitiontime()]
2-element Vector{String}:
 "MPX,0000000022,SET,ACQUISITIONTIME,1"
 "MPX,0000000020,GET,ACQUISITIONTIME"

julia> send_cmd(m, cmds; verbose=true)
[2023-05-27T18:31:57.583]       SET,ACQUISITIONTIME,1 >>> --- <<< SET,ACQUISITIONTIME,0
[2023-05-27T18:31:57.583]       GET,ACQUISITIONTIME >>> --- <<< GET,ACQUISITIONTIME,1.000000,0
2-element Vector{Union{Nothing, SubString{String}}}:
 nothing
 "1.000000"

julia> send_cmd(m, cmd_startacquisition(); verbose=true)
[2023-05-27T18:33:49.568]       CMD,STARTACQUISITION >>> --- <<< CMD,STARTACQUISITION,0
```
Some [common commands](https://github.com/chenspc/Medipix.jl/blob/1a3bb23a1e7d23aa94599237ab63d071ae4825ab/src/Medipix.jl#LL76C1-L103C37) are already generated and [exported](https://github.com/chenspc/Medipix.jl/blob/1a3bb23a1e7d23aa94599237ab63d071ae4825ab/src/Medipix.jl#LL18C1-L45C48) by the package.

## Licence
MIT Licence