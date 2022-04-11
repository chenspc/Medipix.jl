module Medipix

export @medipix
export MedipixCommandPort, MedipixDataPort
export MedipixCMD
export medipix_get, medipix_set, medipix_cmd, medipix_help
export make_medipix_message
export check_medipix_response
export parse_communication
export parse_image

using Sockets

macro medipix(type, name)
    if type ∈ ["GET", "CMD"] 
        fn = Symbol(lowercase(join([type, name], '_')))
        return :($(esc(fn))() = make_medipix_message($type, $name))
    elseif type == "SET"
        fn = Symbol(lowercase(join([type, name], '_')))
        return :($(esc(fn))(v) = make_medipix_message($type, $name; value=v))
    elseif type ∈ ["GET/SET", "SET/GET"]
        # TODO: really want to write a recursive macro here..
        # return :(@medipix "GET" $name; @medipix "SET" $name)
        fn1 = Symbol(lowercase(join(["GET", name], '_')))
        fn2 = Symbol(lowercase(join(["SET", name], '_')))
        return :($(esc(fn1))() = make_medipix_message("GET", $name); $(esc(fn2))(v) = make_medipix_message("SET", $name; value=v))
    else
        @error "$type is not a valid Medipix command type (\"GET\", \"SET\", or \"CMD\")"
        return nothing
    end
end

abstract type MedipixPort end

struct MedipixCommandPort <: MedipixPort 
    ip::IPv4
    port::Int
end
MedipixCommandPort(ip) = MedipixCommandPort(ip, 6341)

struct MedipixDataPort <: MedipixPort 
    ip::IPv4
    port::Int
end
MedipixDataPort(ip) = MedipixDataPort(ip, 6342)

# abstract type MedipixCommand end

# struct MedipixCMD <: MedipixCommand
#     name::String
# end

# abstract type MedipixParameter end
# struct MedipixMutableParameter{T} <: MedipixParameter where T <: Union{Int, Float32, String}
#     name::String
#     value::T
# end

# struct MedipixImmutableParameter{T} <: MedipixParameter where T <: Union{Int, Float32, String}
#     name::String
#     value::T
# end

struct MedipixImage{T} where T 
    id::UInt
    header::String
    data::T
end


function check_connection()
    
end

function check_config()
    
end

# function medipix_get(p::MedipixParameter)
#     type = "GET"
#     msg = make_medipix_message(type, p.name)
# end

# function medipix_set(p::MedipixMutableParameter, v)
#     type = "SET"
#     msg = make_medipix_message(type, p.name; value=v)
# end

# function medipix_cmd(c::MedipixCMD, port::MedipixCommandPort)
#     type = "CMD"
#     msg = make_medipix_message(type, c.name)
# end

# function medipix_help(x::MedipixCommand)
    
# end

function make_medipix_message(type::String, name::String; value="", prefix="MPX")
    body = ',' * type * ',' * name 
    tail = type == "SET" ? ',' * string(value) : ""
    head = prefix * "," * lpad(length(body * tail), 10, "0")
    return head * body * tail
end

function parse_communication(io::IO)
    # TODO: add a mechanism to keep reading until "MPX" appears.
    is_mpx = readuntil(io, ',') == "MPX"
    if is_mpx
        message_size = parse(Int, readuntil(io, ','))
        message = read(io, message_size - 1)
        success, value = check_medipix_response(message)
    else
        # message = Vector{UInt8}()
        success = false
        value = nothing
    end
    return success, value
end

function check_medipix_response(cmd_bytes)
    # TODO: response should be logged in the future
    phrases = split(String(cmd_bytes), ',')
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

function parse_data(io::IO; filepath="", live_processing=true)
    is_mpx = readuntil(io, ',') == "MPX"
    comm_size = parse(Int, readuntil(io, ','))
    hdr_or_frame = peek(io, Char)
    if comm_size > 0
        if hdr_or_frame == 'H'
            hdr = String(read(io, message_size - 1))
            return hdr
        elseif hdr_or_frame == 'M'
            hdr = ""
            image = parse_image(io)
            return image
        else
            @error "Unknown data stream type."
            return nothing
        end
    else
        @error "No data available to read."
    end
end

function parse_image(data_bytes; header_size=768)
    # TODO: change to accept io?
    buffer = IOBuffer(data_bytes)
    header_string = String(read(buffer, default_header_size))

    header_split = split(header_string, ',')
    image_id, header_size, dim_x, dim_y = parse.(Int, getindex(header_split, [2, 3, 5, 6]))

    # TODO: R64 may not work, but can be ignored for now?
    type_dict = Dict("U1" => UInt8, "U8" => UInt8, "U08" => UInt8, 
                    "U16" => UInt16, "U32" => UInt32, "U64" => UInt64, 
                    "R64" => UInt64)
    data_type = type_dict[header_split[7]]

    if header_size != default_header_size
        header_string = String(read(seekstart(buffer), header_size))
    end

    image = Array{data_type}(undef, dim_x, dim_y)
    read!(buffer, image)

    # return image_id, header_string, hton.(image)
    return MedipixImage(image_id, header_string, hton.(image))
end

function to_config(filename, cmds::Vector{String})
    open(filename, "w") do f
        for l in cmds
            cmd = replace(l, r"MPX,[0-9]*,"=>"")
            println(f, cmd)
        end
    end
end
to_config(filename, cmd::String) = to_config(filename, [cmd])

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

end
