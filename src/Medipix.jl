module Medipix

export @medipix
export check_connection, check_config
export make_medipix_message
export parse_communication
export check_medipix_response
export parse_data, parse_image
export to_config, from_config

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

using Sockets: @ip_str, IPv4, connect
using Dates: now
using HDF5: h5write
using Distributed: @spawnat, myid
using .Threads: @spawn

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

struct MedipixData{T}
    id::Int64
    header::String
    data::Matrix
    gen_time::String
    pid::Int
end

function check_connection()
end

function medipix_connect(medipix_ip::IPv4; cmd_port=6341, data_port=6342)
    data_client = connect(medipix_ip, data_port)
     cmd_client = connect(medipix_ip, cmd_port)
   return cmd_client, data_client
end

function make_medipix_message(type::String, name::String; value="", prefix="MPX")
    body = ',' * type * ',' * name 
    tail = type == "SET" ? ',' * string(value) : ""
    head = prefix * "," * lpad(length(body * tail), 10, "0")
    return head * body * tail
end

function send_cmd(cmd_client::IO, cmd::String; verbose=false)
    write(cmd_client, cmd)
    success, value, message = parse_communication(cmd_client)
    if success
        # put!(channel, string(now()) * "   " * message)
        verbose ? println(string(now()) * "   " * message) : nothing
    else
        @warn "Failed to execute command: " * cmd
    end
    return value
end
send_cmd(cmd_client::IO, cmds::Vector{String}; kwargs...) = [send_cmd(cmd_client, cmd; kwargs...) for cmd in cmds]

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
    end
    data_size = parse(Int, readuntil(io, ','))
    hdr_or_frame = peek(io, Char)
    if data_size > 0
        if hdr_or_frame == 'H'
            hdr = String(read(io, data_size - 1))
            # put!(c, MedipixData(0, hdr, Matrix{UInt8}(undef, 1, 1)))
            put!(c, MedipixData(0, hdr, Matrix{UInt8}(undef, 1, 1), string(now()), myid()))
        elseif hdr_or_frame == 'M'
            data = read(io, data_size - 1)
            @async @spawnat :any parse_image(data, c)
            # @spawn parse_image(data, c)
        else
            @error "No data available to read."
        end
    end
    return
end

# function parse_image(c_in::Channel; c_out::Channel; header_size=768)
function parse_image(frame_bytes::Vector{UInt8}, c::Channel; header_size=768)
    # frame_bytes = take!(c)
    header_string = String(frame_bytes[1:header_size])
    header_split = split(header_string, ',')
    image_id, header_size, dim_x, dim_y = parse.(Int, getindex(header_split, [2, 3, 5, 6]))

    # TODO: R64 may not work, but can be ignored for now since it's not the bottleneck.
    type_dict = Dict("U1" => UInt8, "U8" => UInt8, "U08" => UInt8, 
                    "U16" => UInt16, "U32" => UInt32, "U64" => UInt64, 
                    "R64" => UInt16)
    data_type = type_dict[header_split[7]]
    # hton.(read(io, image))? Change endianness if needed. 
    # image = Matrix{data_type}(undef, dim_x, dim_y)
    image = reshape(reinterpret(data_type, frame_bytes[header_size+1:end]), (dim_x, dim_y))
    # put!(c, MedipixData(image_id, header_string, image))
    put!(c, MedipixData(image_id, header_string, image, string(now()), myid()))
    return nothing 
end

function acquisition(cmd_client, data_client, c_out::Channel; config_file::String="", cmds::Vector{String}=[""], verbose=false, kwargs...)
    detector_ready = is_medipix_ready(cmd_client; verbose=verbose)
    if !detector_ready
        send_cmd(cmd_client, cmd_abort())
        send_cmd(cmd_client, cmd_clear())
        send_cmd(cmd_client, cmd_reset())
        sleep(3)
    end
    file_cmds = from_config(config_file; kwargs...)
    send_cmd(cmd_client, [file_cmds; cmds]; verbose=verbose)
    data_server_ready = send_cmd(cmd_client, get_tcpconnected(); verbose=verbose) == "1"
    if data_server_ready 
        n = parse(Int, send_cmd(m, get_numframestoacquire(); verbose=verbose))
        send_cmd(m, cmd_startacquisition(); verbose=verbose)
        # @async for i in range(1, length = n+1)
        for i in range(1, length = n+1)
            # parse_data(m.data_client, c_out)
            parse_data(m.data_client, c_out[mod(i, length(c_out))+1])
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

function is_medipix_ready(cmd_client; verbose=false)
    status = send_cmd(cmd_client, get_detectorstatus())
    isready = status == "0" 
    if verbose == true
        status_dict = Dict("0" => "Idle", "1" => "Busy", "2" => "Standby", "3" => "Error", "4" => "Armed", "5" => "Init")
        println(string(now()) * "   " * "Detector status: " * status_dict[status])
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

function file_writer(filename::String, c; max_digits=8)
    @async while isopen(c) 
        wait(c)
        image = take!(c)
        length(digits(image.id)) > max_digits ? max_digits += 4 : nothing
        id_str = lpad(image.id, max_digits, "0")
        group_name = id_str[1:end-4]
        data_name = id_str[end-3:end]
        h5write(filename * ".h5", "/group_" * group_name * "/image_" * data_name, image.data)
        h5write(filename * ".h5", "/group_" * group_name * "/header_" * data_name, strip(image.header, '\0'))
        h5write(filename * ".h5", "/group_" * group_name * "/gen_time_" * data_name, image.gen_time)
        h5write(filename * ".h5", "/group_" * group_name * "/pid_" * data_name, image.pid)
        # h5write(filename * ".h5", "/group_" * group_name * "/write_time_" * data_name, string(now()))
    end
end

function file_writers(filename::String, c; max_digits=8, nwriter=2, proc_ids=range(2, length=nwriter))
    filenames = [filename * lpad(i, 4, "0") for i in 1:nwriter]
    for w in nwriter
        @spawnat proc_ids[w] file_writer(filenames[w], c; max_digits=max_digits)
    end
end

end # module



# do_scan(cmd_client, data_client, 128, 128)
# function do_scan(cmd_client, data_client, nx, ny)
#     send_cmd(cmd_client, set_scanx(nx))
#     send_cmd(cmd_client, set_scany(ny))
#     c = Channel(nx * ny + 1)
#     send_cmd(cmd_client, cmd_startacquisition(); verbose=true)
#     [parse_data(data_client, c) for i in range(1, length=nx * ny + 1)]
#     return c
# end

# Threads.@threads for _ in 1:nthreads()
#     for n in c_data
#         parse_data
#     end

