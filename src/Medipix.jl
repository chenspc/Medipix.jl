module Medipix

export MedipixData
export MedipixConnection
export @medipix
export medipix_connect, medipix_connect!
export check_connection
export close_connection
export send_cmd
export make_pid_dict
export acquisition
export to_config, from_config
export is_medipix_ready
export abort_and_clear
export troubleshoot
export file_writer
export run_stream
export run_acquisition

export cmd_reset
export cmd_abort
export cmd_startacquisition
export cmd_stopacquisition
export cmd_clearerror
export cmd_softtrigger
export get_detectorstatus
export get_errorcode
export get_tcpconnected
export get_continuousrw, set_continuousrw
export get_acquisitiontime, set_acquisitiontime
export get_acquisitionperiod, set_acquisitionperiod
export get_counterdepth, set_counterdepth
export get_numframestoacquire, set_numframestoacquire
export get_numframespertrigger, set_numframespertrigger
export get_runheadless, set_runheadless
export get_fileformat, set_fileformat
export get_imagesperfile, set_imagesperfile
export get_fileenable, set_fileenable
export get_usetimestamping, set_usetimestamping
export get_triggerstart, set_triggerstart
export get_triggerstop, set_triggerstop
export get_triggeroutttl, set_triggeroutttl
export get_triggeroutttlinvert, set_triggeroutttlinvert
export get_scanx, set_scanx
export get_scany, set_scany
export get_selectchips, set_selectchips
export get_scantriggermode, set_scantriggermode

using Sockets: @ip_str, IPv4, TCPSocket, connect
export @ip_str
using Dates
using HDF5
using Distributed: @spawnat, myid, remotecall
using Dates
using IterTools: product

export load_mib

macro medipix(type, name)
    if type ∈ ["GET", "CMD"] 
        fn = Symbol(lowercase(join([type, name], '_')))
        return :($(esc(fn))() = make_medipix_message($type, $name))
    elseif type == "SET"
        fn = Symbol(lowercase(join([type, name], '_')))
        return :($(esc(fn))(v) = make_medipix_message($type, $name; value=v))
    elseif type ∈ ["GET/SET", "SET/GET"]
        # TODO: really want to write a recursive macro here..
        fn1 = Symbol(lowercase(join(["GET", name], '_')))
        fn2 = Symbol(lowercase(join(["SET", name], '_')))
        return :($(esc(fn1))() = make_medipix_message("GET", $name); $(esc(fn2))(v) = make_medipix_message("SET", $name; value=v))
    else
        @error "$type is not a valid Medipix command type (\"GET\", \"SET\", or \"CMD\")"
        return nothing
    end
end

# Common commands
@medipix "CMD" "RESET"
@medipix "CMD" "ABORT"
@medipix "CMD" "STARTACQUISITION"
@medipix "CMD" "STOPACQUISITION"
@medipix "CMD" "CLEARERROR"
@medipix "CMD" "SOFTTRIGGER"
@medipix "GET" "DETECTORSTATUS"
@medipix "GET" "ERRORCODE"
@medipix "GET" "TCPCONNECTED"
@medipix "GET/SET" "CONTINUOUSRW"
@medipix "GET/SET" "ACQUISITIONTIME" 
@medipix "GET/SET" "ACQUISITIONPERIOD"
@medipix "GET/SET" "COUNTERDEPTH"
@medipix "GET/SET" "NUMFRAMESTOACQUIRE"
@medipix "GET/SET" "NUMFRAMESPERTRIGGER"
@medipix "GET/SET" "RUNHEADLESS"
@medipix "GET/SET" "FILEFORMAT"
@medipix "GET/SET" "IMAGESPERFILE"
@medipix "GET/SET" "FILEENABLE"
@medipix "GET/SET" "USETIMESTAMPING"
@medipix "GET/SET" "TRIGGERSTART"
@medipix "GET/SET" "TRIGGERSTOP"
@medipix "GET/SET" "TRIGGEROUTTTL"
@medipix "GET/SET" "TriggerOutTTLInvert"
@medipix "GET/SET" "SCANX"
@medipix "GET/SET" "SCANY"
@medipix "GET/SET" "SELECTCHIPS"
@medipix "GET/SET" "SCANTRIGGERMODE"

struct MedipixData
    id::Int64
    header::String
    data::Matrix
end

mutable struct MedipixConnection
    ip::IPv4
    cmd_port::Int
    data_port::Int
    cmd_client::TCPSocket
    data_client::TCPSocket
    cmd_log::Vector{String}
end
MedipixConnection(ip::IPv4, cmd_port::Int, data_port::Int) = MedipixConnection(ip, cmd_port, data_port, connect(ip, cmd_port), connect(ip, data_port), Vector{String}())
MedipixConnection(ip::IPv4) = MedipixConnection(ip, 6341, 6342)

abstract type AbstractMIBHeader end

struct MIBHeader <: AbstractMIBHeader
    id::Int
    offset::Int
    nchip::Int
    dims::Vector{Int}
    data_type::DataType
    chip_dims::Vector{Int}
    time::DateTime
    exposure_s::Float64
    image_bit_depth::Int
    raw::Bool
end

function load_mib(filepath::AbstractString; kwargs...)
    first_header = firstheader(filepath)
    images, headers = read_mib(filepath, first_header; kwargs...)
    return images, headers
end

function read_mib(filepath::AbstractString, first_header::AbstractMIBHeader; range=[1,typemax(Int)])
    offset = first_header.offset
    type = first_header.data_type
    dims = first_header.dims
    raw = first_header.raw
    image_bit_depth = first_header.image_bit_depth

    fid = open(filepath, "r")
    headers = Vector{MIBHeader}()
    if raw
        depth_dict = Dict(1 => UInt8, 6 => UInt8, 12 => UInt16,
                          24 => UInt32, 48 => UInt64)
        type = depth_dict[image_bit_depth]
    end
        buffer = Array{type}(undef, dims[1], dims[2])
        images = Vector{Array{type, 2}}()

    n = 0
    while eof(fid) == false && n < range[2]
            header_string = read(fid, offset)
            read!(fid, buffer)
            n += 1
            if n >= range[1]
                push!(headers, make_mibheader(String(header_string); id=n))
                push!(images, hton.(buffer))
            end
    end
    close(fid)
    return images, headers
end

function firstheader(filepath)
    fid = open(filepath)
    trial = split(String(read(fid, 768)), ",")
    offset = parse(Int, trial[3])
    seekstart(fid)
    header_string = String(read(fid, offset))
    close(fid)
    first_header = make_mibheader(header_string; id=1)
    return first_header
end

function make_mibheader(header_string::AbstractString; id=0)
    header = split(header_string, ",")
    offset = parse(Int, header[3])
    nchip = parse(Int, header[4])
    dims = parse.(Int, header[5:6])
    type_dict = Dict("U1" => UInt8, "U8" => UInt8, "U08" => UInt8, "U16" => UInt16,
                     "U32" => UInt32, "U64" => UInt64, "R64" => UInt64)
    data_type = type_dict[header[7]]
    chip_dims = parse.(Int, split(lstrip(header[8]), "x"))
    time = DateTime(header[10][1:end-3], "y-m-d H:M:S.s")
    exposure_s = parse(Float64, header[11])
    image_bit_depth = parse(Int, header[end-1])
    raw = header[7] == "R64"
    return MIBHeader(id, offset, nchip, dims, data_type, chip_dims, time, exposure_s, image_bit_depth, raw)
end

function check_connection(m::MedipixConnection)
    if !isopen(m.cmd_client)
        m.cmd_client = connect(m.ip, m.cmd_port)
        print("Command client reconnected.")
    end
    if send_cmd(m, get_tcpconnected(); verbose=true) == "0"
        m.data_client = connect(m.ip, m.data_port)
        print("Data client reconnected.")
    end
    return nothing
end

function close_connection(m::MedipixConnection; log::String="")
    close(m.cmd_client)
    close(m.data_client)
    if log != ""
        open(log, "a") do f
            [println(f, cl) for cl in m.cmd_log]
        end
    end
    return nothing
end

function medipix_connect(medipix_ip::IPv4; cmd_port=6341, data_port=6342)
    data_client = connect(medipix_ip, data_port)
     cmd_client = connect(medipix_ip, cmd_port)
   return cmd_client, data_client
end
medipix_connect(; kwargs...) = medipix_connect(ip"127.0.0.1"; kwargs...)

function medipix_connect!(m::MedipixConnection)
    m.cmd_client, m.data_client = medipix_connect(m.ip; cmd_port=m.cmd_port, data_port=m.data_port)
end

function make_medipix_message(type::String, name::String; value="", prefix="MPX")
    body = ',' * type * ',' * name 
    tail = type == "SET" ? ',' * string(value) : ""
    head = prefix * "," * lpad(length(body * tail), 10, "0")
    return head * body * tail
end

function is_medipix_message(s::String)
    length(s) >= 15 && s[1:3] == "MPX"
end

function send_cmd(m::MedipixConnection, cmd::String; verbose=false)
    if is_medipix_message(cmd)
        write(m.cmd_client, cmd)
        success, value, message = parse_communication(m.cmd_client)
        log_message = "[" * string(now()) * "]\t" * cmd[16:end] * " >>> --- <<< " * message
        push!(m.cmd_log, log_message)
        if success
            verbose ? println(log_message) : nothing
        else
            @warn "Failed to execute command: " * cmd[16:end]
        end
    else
        value = nothing
    end
    return value
end
send_cmd(m, cmds::Vector{String}; kwargs...) = [send_cmd(m, cmd; kwargs...) for cmd in cmds]

function parse_communication(io::IO)
    while true
        buffer = readuntil(io, ',')
        if length(buffer) >= 3 && buffer[end-2:end] == "MPX"
            break
        end
    end
    message_size = parse(Int, readuntil(io, ','))
    message = String(read(io, message_size - 1))
    success, value = check_medipix_response(message)
    return success, value, message
end

function check_medipix_response(message)
    phrases = split(message, ',')
    if length(phrases) == 3
        type, name, status = phrases
        value = nothing
    elseif length(phrases) == 4
        type, name, value, status = phrases
    end

    if status == "0"
        success = true
    elseif status == "1"
        @warn "The system is busy."
        success = false
    elseif status == "2"
        @error "Unrecognised command: $name."
        success = false
    elseif status == "3"
        @error "The value $value is out of the range of $name."
        success = false
    end
    return success, value
end

function parse_data(io::IO, fw; pid=1)
    while true
        buffer = readuntil(io, ',')
        if length(buffer) >= 3 && buffer[end-2:end] == "MPX"
            break
        end
    end

    data_size = parse(Int, readuntil(io, ','))
    if data_size > 0
        data = read(io, data_size - 1)
        if pid == 1 
            # @spawnat :any parse_image(data, fw)
            finalize(remotecall(parse_image, 2, data, fw))
        else
            finalize(remotecall(parse_image, pid, data, fw))
        end
    else
        @error "No data available to read."
    end
    return nothing
end

function parse_image(data::Vector{UInt8}, fw)
    hdr_or_frame = convert(Char, data[1])

    if hdr_or_frame == 'H'
        hdr = String(data)
        fw(MedipixData(0, hdr, Matrix{UInt8}(undef, 1, 1)))
    elseif hdr_or_frame == 'M'
        header_string = String(data[1:768])
        header_split = split(header_string, ',')
        image_id, header_size, dim_x, dim_y = parse.(Int, getindex(header_split, [2, 3, 5, 6]))

        # TODO: R64 may not work, but can be ignored for now since it's not the bottleneck.
        type_dict = Dict("U1" => UInt8, "U8" => UInt8, "U08" => UInt8, 
                        "U16" => UInt16, "U32" => UInt32, "U64" => UInt64, 
                        "R64" => UInt16)

        data_type = type_dict[header_split[7]]
        image = hton.(reshape(reinterpret(data_type, data[header_size+1:end]), (dim_x, dim_y)))
        finalize(@async fw(MedipixData(image_id, header_string, image)))
    else
        @error "Unknown data stream type."
    end
    return nothing 
end

function make_pid_dict(scan_size, block_size)
    pid_dict = zeros(Int, first(scan_size), last(scan_size))

    p1 = collect(Iterators.partition(1:first(scan_size), first(block_size)))
    p2 = collect(Iterators.partition(1:last(scan_size), last(block_size)))
    p = collect(product(p1, p2))

    for i in eachindex(p)
        map(x -> pid_dict[x...] = i, product(p[i]...))
    end
    return pid_dict
end

function acquisition(m::MedipixConnection, fw; pid_dict=Matrix{Int}[], config_file::String="", cmds::Vector{String}=[""], verbose=false, kwargs...)
    check_connection(m)
    if !is_medipix_ready(m; verbose=verbose)
        abort_and_clear(m; verbose=verbose)
    end

    if !is_medipix_ready(m; verbose=verbose)
        send_cmd(m, cmd_reset(); verbose=verbose)
        sleep(10)
        check_connection(m)
        abort_and_clear(m; verbose=verbose)
        medipix_connect!(m)
    end

    if isfile(config_file)
        file_cmds = from_config(config_file; kwargs...)
    else
        file_cmds = [""]
    end

    file_cmds = isfile(config_file) ? from_config(config_file; kwargs...) : [""]
    send_cmd(m, vcat(file_cmds, cmds); verbose=verbose)
    data_server_ready = send_cmd(m, get_tcpconnected(); verbose=verbose) == "1"

    if data_server_ready 
        n = parse(Int, send_cmd(m, get_numframestoacquire(); verbose=verbose))
        send_cmd(m, cmd_startacquisition(); verbose=verbose)
        for i in range(1, length = n+1)
            if isempty(pid_dict)
                parse_data(m.data_client, fw)
            elseif i == 1
                parse_data(m.data_client, fw; pid=2)
            else
                parse_data(m.data_client, fw; pid=pid_dict[i-1]+1)
            end
        end
    else
        @warn "Data client is not connected to the server. Acquisition aborted."
    end
    return nothing
end

function to_config(filename::String, cmds::Vector{String})
    open(filename, "w") do f
        for l in cmds
            cmd = replace(l, r"MPX,[0-9]*,"=>"")
            println(f, cmd)
        end
    end
end
to_config(filename::String, cmd::String) = to_config(filename, [cmd])

function from_config(config_input::AbstractString; prefix="MPX", loaded_files=Vector{String}(), print_trace=false)
    cmds = Vector{String}()
    if isfile(config_input)
        if config_input ∈ loaded_files
            @warn "Config file loop detected. $config_input has already been loaded and will be skipped."
        else
            append!(loaded_files, [config_input])
            open(config_input) do f
                while !eof(f) 
                l = readline(f)         
                append!(cmds, from_config(l; prefix=prefix, loaded_files=loaded_files))
                end
            end
        end
    else
        append!(cmds, [prefix * "," * lpad(length(config_input) + 1, 10, "0") * "," * config_input])
    end
    print_trace ? println(join(loaded_files, " => ")) : nothing
    return cmds 
end

function is_medipix_ready(m::MedipixConnection; verbose=false)
    status = send_cmd(m, get_detectorstatus(); verbose=verbose)
    isready = status == "0" 
    if verbose == true
        status_dict = Dict("0" => "Idle", "1" => "Busy", "2" => "Standby", "3" => "Error", "4" => "Armed", "5" => "Init")
        println("[" * string(now()) * "]\t" * "Detector status: " * status_dict[status])
    end
    return isready
end

function abort_and_clear(m::MedipixConnection; verbose=false)
    send_cmd(m, cmd_abort(); verbose=verbose)
    sleep(3)
    push!(m.cmd_log, "[" * string(now()) *"]\tDUMP: " * String(readavailable(m.cmd_client)))
    send_cmd(m, cmd_clearerror(); verbose=verbose)
end

function troubleshoot(m::MedipixConnection; do_not_reset=true, verbose=true)
    status_dict = Dict("0" => "Idle", "1" => "Busy", "2" => "Standby", "3" => "Error", "4" => "Armed", "5" => "Init")
    status = status_dict(send_cmd(c, get_detectorstatus(); verbose=verbose))
    if status == "Busy"
        abort_and_clear(m; verbose=verbose)
    elseif status == "Standby"
    elseif status == "Error"
        abort_and_clear(m; verbose=verbose)
    elseif status == "Armed"
    elseif status == "Init"
    else
    end
    return nothing
end

function make_image(data::Vector{UInt8})
    hdr_or_frame = convert(Char, data[1])

    if hdr_or_frame == 'H'
        hdr = String(data)
        return MedipixData(0, hdr, Matrix{UInt8}(undef, 1, 1))
    elseif hdr_or_frame == 'M'
        header_string = String(data[1:768])
        header_split = split(header_string, ',')
        image_id, header_size, dim_x, dim_y = parse.(Int, getindex(header_split, [2, 3, 5, 6]))

        # TODO: R64 may not work, but can be ignored for now since it's not the bottleneck.
        type_dict = Dict("U1" => UInt8, "U8" => UInt8, "U08" => UInt8, 
                        "U16" => UInt16, "U32" => UInt32, "U64" => UInt64, 
                        "R64" => UInt16)

        data_type = type_dict[header_split[7]]
        image = hton.(reshape(reinterpret(data_type, data[header_size+1:end]), (dim_x, dim_y)))
        return MedipixData(image_id, header_string, image)
    else
        @error "Unknown data stream type."
    end
    
    return nothing
end

function producer(channel::Channel, io, frames=0)
    counter = 0
    while isopen(channel)
        if frames > 0 && counter >= frames
            break
        end
        while true
            buffer = readuntil(io, ',')
            if length(buffer) >= 3 && buffer[end-2:end] == "MPX"
                break
            end
        end

        data_size = parse(Int, readuntil(io, ','))
        if data_size > 0
            data = read(io, data_size - 1)
        else
            @error "No data available to read."
        end
        put!(channel, make_image(data))
        counter += 1
    end
    return nothing
end

function consumer(channel::Channel, filepath, frames=0; nfiles=1, file_indices=Int[])
    counter = 0
    file_handles = Dict{Int, HDF5.File}()
    for digit in 1:nfiles
        file_handles[digit] = h5open(filepath * "_" * lpad(string(digit), 3, "0") * ".h5", "w")
    end

    function write_image(i, image; file_index=0)
        if file_index == 0
            file_idx = i % nfiles == 0 ? nfiles : i % nfiles
        else
            file_idx = file_index
        end
        file_to_write = file_handles[file_idx]
        write_dataset = "image_" * lpad(string(i), 8, "0")
        file_to_write[write_dataset] = image
    end

    try
        while isopen(channel)
            if frames > 0 && counter >= frames
                break
            end
            mdata = take!(channel)
            fi = 1 <= mdata.id <= length(file_indices) ? file_indices[mdata.id] : 0
            Threads.@spawn write_image(mdata.id, mdata.data; file_index=fi)
            counter += 1
        end
    finally
        sleep(1)
        close(channel)
        foreach(close, values(file_handles))
    end
end

function run_stream(io, filepath; frames=0, channel_size=10000, nfiles=1, file_indices=Int[])
    channel = Channel(channel_size)
    @async producer(channel, io, frames)
    consumer(channel, filepath, frames; nfiles=nfiles, file_indices=file_indices)
    return nothing
end

function run_acquisition(m::MedipixConnection, filepath; config_file::String="", cmds::Vector{String}=[""], verbose=false, nfiles=1, file_indices=Int[], kwargs...)
    check_connection(m)
    if !is_medipix_ready(m; verbose=verbose)
        abort_and_clear(m; verbose=verbose)
    end

    if !is_medipix_ready(m; verbose=verbose)
        send_cmd(m, cmd_reset(); verbose=verbose)
        sleep(10)
        check_connection(m)
        abort_and_clear(m; verbose=verbose)
        medipix_connect!(m)
    end

    if isfile(config_file)
        file_cmds = from_config(config_file; kwargs...)
    else
        file_cmds = [""]
    end

    file_cmds = isfile(config_file) ? from_config(config_file; kwargs...) : [""]
    send_cmd(m, vcat(file_cmds, cmds); verbose=verbose)
    data_server_ready = send_cmd(m, get_tcpconnected(); verbose=verbose) == "1"

    if data_server_ready 
        n = parse(Int, send_cmd(m, get_numframestoacquire(); verbose=verbose))
        send_cmd(m, cmd_startacquisition(); verbose=verbose)
        run_stream(m.data_client, filepath; frames=n+1, nfiles=nfiles, file_indices=file_indices)
    else
        @warn "Data client is not connected to the server. Acquisition aborted."
    end
    return nothing
end

function file_writer(filename::String; max_digits=8, time_stamp=true)
    if time_stamp
        path_split = splitpath(filename) |> x -> insert!(x, length(x), Dates.format(now(), "yyyymmdd_HHMMSS"))
        filename = joinpath(path_split)
        dirname = joinpath(path_split[1:end-1])
        isdir(dirname) ? nothing : mkdir(dirname)
    end
    function fw(mdata)
        length(digits(mdata.id)) > max_digits ? max_digits += 4 : nothing
        id_str = lpad(mdata.id, max_digits, "0")
        h5write(filename * "_" * lpad(string(myid() - 1), 3, "0") * ".h5", "/image_" * id_str, mdata.data)
        h5write(filename * "_" * lpad(string(myid() - 1), 3, "0") * ".h5", "/header_" * id_str, strip(mdata.header, '\0'))
    end
    return fw
end

end # module
