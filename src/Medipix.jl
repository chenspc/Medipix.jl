module Medipix

export MedipixData
export MedipixConnection
export @medipix
export medipix_connect, medipix_connect!
export check_connection
export close_connection
export make_medipix_message
export send_cmd
export parse_communication
export check_medipix_response
export parse_data, parse_image
export acquisition
export to_config, from_config
export is_medipix_ready
export troubleshoot
export ptycho_initialisation
export file_writer

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
export get_scanx, set_scanx
export get_scany, set_scany

using Sockets: @ip_str, IPv4, TCPSocket, connect
export @ip_str
using Dates: now
using HDF5: h5open, attributes, h5write

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
@medipix "GET/SET" "SCANX"
@medipix "GET/SET" "SCANY"

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
end
MedipixConnection(ip::IPv4, cmd_port::Int, data_port::Int) = MedipixConnection(ip, cmd_port, data_port, connect(ip, cmd_port), connect(ip, data_port))
MedipixConnection(ip::IPv4) = MedipixConnection(ip, 6341, 6342)

function check_connection(m::MedipixConnection)
    if !isopen(m.cmd_client)
        m.cmd_client = connect(m.ip, m.cmd_port)
        print("Command client reconnected.")
    end
    if send_cmd(m.cmd_client, get_tcpconnected(); verbose=true) == "0"
        m.data_client = connect(m.ip, m.data_port)
        print("Data client reconnected.")
    end
    return nothing
end

function close_connection(m::MedipixConnection)
    close(m.cmd_client)
    close(m.data_client)
    return nothing
end

function medipix_connect(medipix_ip::IPv4; cmd_port=6341, data_port=6342)
    data_client = connect(medipix_ip, data_port)
     cmd_client = connect(medipix_ip, cmd_port)
   return cmd_client, data_client
end

function medipix_connect!(m::MedipixConnection)
    m.cmd_client, m.data_client = medipix_connect(m.ip; cmd_port=m.cmd_port, data_port=m.data_port)
end

function make_medipix_message(type::String, name::String; value="", prefix="MPX")
    body = ',' * type * ',' * name 
    tail = type == "SET" ? ',' * string(value) : ""
    head = prefix * "," * lpad(length(body * tail), 10, "0")
    return head * body * tail
end

is_medipix_message(s::String) = length(s) >= 15 && s[1:3] == "MPX"

function send_cmd(cmd_client::IO, cmd::String; verbose=false)
    if is_medipix_message(cmd)
        write(cmd_client, cmd)
        success, value, message = parse_communication(cmd_client)
        if success
            # put!(channel, string(now()) * "\t" * cmd * " >>> --- <<< " * message) 
            verbose ? println(string(now()) * "\t" * cmd * " >>> --- <<< " * message) : nothing
        else
            @warn "Failed to execute command: " * cmd
        end
    else
        value = nothing
    end
    return value
end
send_cmd(cmd_client::IO, cmds::Vector{String}; kwargs...) = [send_cmd(cmd_client, cmd; kwargs...) for cmd in cmds]
send_cmd(m::MedipixConnection, cmd; kwargs...) = send_cmd(m.cmd_client, cmd; kwargs...)

function parse_communication(io::IO)
    is_mpx = false
    while !is_mpx
        buffer = readuntil(io, ',')
        if length(buffer) >= 3
            is_mpx = buffer[end-2:end] == "MPX"
        end
    end
    message_size = parse(Int, readuntil(io, ','))
    message = String(read(io, message_size - 1))
    success, value = check_medipix_response(message)
    return success, value, message
end

function check_medipix_response(message)
    # TODO: Add an option to log the response 
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

function parse_data(io::IO, c::Channel; live_processing=true)
    is_mpx = false
    while isopen(c)
        while !is_mpx
            buffer = readuntil(io, ',')
            if length(buffer) >= 3
                is_mpx = buffer[end-2:end] == "MPX"
            end
        end
        data_size = parse(Int, readuntil(io, ','))
        hdr_or_frame = peek(io, Char)
        if is_mpx && data_size > 0
            if hdr_or_frame == 'H'
                hdr = String(read(io, data_size - 1))
                put!(c, MedipixData(0, hdr, Matrix{UInt8}(undef, 1, 1)))
                return hdr
            elseif hdr_or_frame == 'M'
                data = read(io, data_size - 1)
                parse_image(data, c)
                return data
            else
                @error "Unknown data stream type."
            end
        else
            @error "No data available to read."
        end
    end
    return
end

function parse_image(frame_bytes::Vector{UInt8}, c::Channel; header_size=768)
    header_string = String(frame_bytes[1:header_size])
    header_split = split(header_string, ',')
    image_id, header_size, dim_x, dim_y = parse.(Int, getindex(header_split, [2, 3, 5, 6]))

    # TODO: R64 may not work, but can be ignored for now since it's not the bottleneck.
    type_dict = Dict("U1" => UInt8, "U8" => UInt8, "U08" => UInt8, 
                    "U16" => UInt16, "U32" => UInt32, "U64" => UInt64, 
                    "R64" => UInt16)
    data_type = type_dict[header_split[7]]
    image = reshape(reinterpret(data_type, frame_bytes[header_size+1:end]), (dim_x, dim_y))
    put!(c, MedipixData(image_id, header_string, image))
    return nothing 
end

function acquisition(m::MedipixConnection, c_out::Channel; config_file::String="", cmds::Vector{String}=[""], verbose=false, kwargs...)
    check_connection(m)
    
    if !is_medipix_ready(m.cmd_client; verbose=verbose)
        send_cmd(m.cmd_client, cmd_abort(); verbose=verbose)
        sleep(3)
        send_cmd(m.cmd_client, cmd_clearerror(); verbose=verbose)
    else
        if !is_medipix_ready(m.cmd_client; verbose=verbose)
            send_cmd(m.cmd_client, cmd_reset(); verbose=verbose)
            sleep(10)
            send_cmd(m.cmd_client, cmd_abort(); verbose=verbose)
            sleep(3)
            send_cmd(m.cmd_client, cmd_clearerror(); verbose=verbose)
            medipix_connect!(m)
            check_connection(m)
        end
    end
    if isfile(config_file)
        file_cmds = from_config(config_file; kwargs...)
    else
        file_cmds = [""]
    end
    send_cmd(m.cmd_client, vcat(file_cmds, cmds); verbose=verbose)
    data_server_ready = send_cmd(m.cmd_client, get_tcpconnected(); verbose=verbose) == "1"
    if data_server_ready 
        n = parse(Int, send_cmd(m.cmd_client, get_numframestoacquire(); verbose=verbose))
        send_cmd(m.cmd_client, cmd_startacquisition(); verbose=verbose)
        @async for i in range(1, length = n+1)
            parse_data(m.data_client, c_out)
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

function is_medipix_ready(cmd_client::TCPSocket; verbose=false)
    status = send_cmd(cmd_client, get_detectorstatus(); verbose=verbose)
    isready = status == "0" 
    if verbose == true
        status_dict = Dict("0" => "Idle", "1" => "Busy", "2" => "Standby", "3" => "Error", "4" => "Armed", "5" => "Init")
        println(string(now()) * "   " * "Detector status: " * status_dict[status])
    end
    return isready
end
is_medipix_ready(m::MedipixConnection; kwargs...) = is_medipix_ready(m.cmd_client; kwargs...)

function troubleshoot(m::MedipixConnection; do_not_reset=true, verbose=true)
    status_dict = Dict("0" => "Idle", "1" => "Busy", "2" => "Standby", "3" => "Error", "4" => "Armed", "5" => "Init")
    status = status_dict(send_cmd(cmd_client, get_detectorstatus(); verbose=verbose))
    if status == "Busy"
        send_cmd(m.cmd_client, cmd_clearerror(); verbose=verbose)
    elseif status == "Standby"
    elseif status == "Error"
        send_cmd(m.cmd_client, cmd_clearerror(); verbose=verbose)
    elseif status == "Armed"
    elseif status == "Init"
    else
    end
    return nothing
end

function ptycho_initialisation(n_data::Int, n_processors::Int, n_writer::Int)
    cmd_client, data_client = medipix_connect(medipix_ip)
    c_data
    return c_d2p, c_p2w
end 

function file_writer(filename::String, c_in::Channel; n_writers=1)
    filenames = [filename * "_" * lpad(i, 4, "0") for i in 1:n_writers]
    @async for w in 1:n_writers
        while isopen(c_in) 
            wait(c_in)
            image = take!(c_in)
            data_name = "frame_" * lpad(image.id, 8, "0")
            h5write(filenames[w] * ".h5", data_name * "/image", image.data)
            h5write(filenames[w] * ".h5", data_name * "/header", strip(image.header, '\0'))
        end
    end
end

end # module
