using Sockets

medipix_ip = ip"127.0.0.1"

hdr_string = "MPX,0000002049,HDR,\t\r\nTime and Date Stamp (day, mnth, yr, hr, min, s):\t26/02/2021 09:53:33\r\nChip ID:\tW530_J6,W530_L6,W530_K5,W530_B5\r\nChip Type (Medipix 3.0, Medipix 3.1, Medipix 3RX):\tMedipix 3RX\r\nAssembly Size (NX1, 2X2):\t   2x2\r\nChip Mode  (SPM, CSM, CM, CSCM):\tSPM\r\nCounter Depth (number):\t6\r\nGain:\tSLGM\r\nActive Counters:\tAlternating\r\nThresholds (keV):\t1.000000E+1,5.000000E+2,0.000000E+0,0.000000E+0,0.000000E+0,0.000000E+0,0.000000E+0,0.000000E+0\r\nDACs:\t033,511,000,000,000,000,000,000,100,255,100,125,100,100,065,100,069,030,128,004,255,145,128,199,191,511,511; 030,511,000,000,000,000,000,000,100,255,100,125,100,100,066,100,064,030,128,004,255,143,128,201,193,511,511; 032,511,000,000,000,000,000,000,100,255,100,125,100,100,066,100,071,030,128,004,255,147,128,191,184,511,511; 030,511,000,000,000,000,000,000,100,255,100,125,100,100,066,100,074,030,128,004,255,147,128,191,184,511,511\r\nbpc File:\tc:\\MERLIN_Quad_Config\\W530_J6\\W530_J6_SPM.bpc,c:\\MERLIN_Quad_Config\\W530_L6\\W530_L6_SPM.bpc,c:\\MERLIN_Quad_Config\\W530_K5\\W530_K5_SPM.bpc,c:\\MERLIN_Quad_Config\\W530_B5\\W530_B5_SPM.bpc\r\nDAC File:\tc:\\MERLIN_Quad_Config\\W530_J6\\W530_J6_SPM.dacs,c:\\MERLIN_Quad_Config\\W530_L6\\W530_L6_SPM.dacs,c:\\MERLIN_Quad_Config\\W530_K5\\W530_K5_SPM.dacs,c:\\MERLIN_Quad_Config\\W530_B5\\W530_B5_SPM.dacs\r\nGap Fill Mode:\tNone\r\nFlat Field File:\tNone\r\nDead Time File:\tDummy (C:\\<NUL>\\)\r\nAcquisition Type (Normal, Th_scan, Config):\tNormal\r\nFrames in Acquisition (Number):\t65536\r\nFrames per Trigger (Number):\t65536\r\nTrigger Start (Positive, Negative, Internal):\tRising Edge\r\nTrigger Stop (Positive, Negative, Internal):\tRising Edge\r\nSensor Bias (V):\t120 V\r\nSensor Polarity (Positive, Negative):\tPositive\r\nTemperature (C):\tBoard Temp 38.907883 Deg C\r\nHumidity (%):\tBoard Humidity -0.026184 \r\nMedipix Clock (MHz):\t120MHz\r\nReadout System:\tMerlin Quad\r\nSoftware Version:\t0.75.4.84\r\nEnd\t                                                                                                                                                                                                         "
frame_header_string = "MPX,0000000769,MQ1,000001,00768,04,1024,0256,R64,   2x2,0F,2021-02-26 09:54:33.292651,0.000416,0,0,0,1.000000E+1,5.000000E+2,0.000000E+0,0.000000E+0,0.000000E+0,0.000000E+0,0.000000E+0,0.000000E+0,3RX,033,511,000,000,000,000,000,000,100,255,100,125,100,100,065,100,069,030,128,004,255,145,128,199,191,511,511,3RX,030,511,000,000,000,000,000,000,100,255,100,125,100,100,066,100,064,030,128,004,255,143,128,201,193,511,511,3RX,032,511,000,000,000,000,000,000,100,255,100,125,100,100,066,100,071,030,128,004,255,147,128,191,184,511,511,3RX,030,511,000,000,000,000,000,000,100,255,100,125,100,100,066,100,074,030,128,004,255,147,128,191,184,511,511,MQ1A,2021-02-26T09:54:33.292651358Z,416010ns,6,\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0"
start_msg = make_medipix_message("CMD", "STARTACQUISITION")

temp_file_path = "/Users/chen/Downloads/temp.txt"; 
temp_hdr_path = "/Users/chen/Downloads/temp_hdr.txt"; 
temp_data_path = "/Users/chen/Downloads/temp_data.txt"; 

function server_startup(server_ip; cmd_port=6341, data_port=6342)
    cmd_server = listen(server_ip, cmd_port)
    data_server = listen(server_ip, data_port)
    return cmd_server, data_server
end

cmd_server, data_server = server_startup(medipix_ip)
@async global cmd_sock = accept(cmd_server)
@async global data_sock = accept(data_server)

function client_startup(server_ip; cmd_port=6341, data_port=6342)
    cmd_client = connect(server_ip, cmd_port)
    data_client = connect(server_ip, data_port)
    return cmd_client, data_client
end

# cmd_client = connect(medipix_ip, 6341)
# data_client = connect(medipix_ip, 6342)
cmd_client, data_client = client_startup(medipix_ip)

global keep_medipix_servers_on = true
global green_light = false

write(cmd_client, "a")
# @async begin
    # while keep_medipix_servers_on 
        # cmd_sock = accept(cmd_server)
        # @async while isopen(cmd_sock) && bytesavailable(cmd_sock) > 0 && keep_medipix_servers_on
        @async while isopen(cmd_sock) && bytesavailable(cmd_sock) > 0
            cmd_comm = parse_medipix_communication(cmd_sock)
            # if !isempty(cmd_comm) 
                cmd_string = String(cmd_comm)
                println(cmd_string*" from server")
                # write(stdout, cmd_string)
                # write(cmd_sock, cmd_string)
                
                if isopen(data_sock) && cmd_string == "CMD,STARTACQUISITION"
                    write(data_sock, hdr_string * frame_header_string)
                    cmd_string = ""
                else
                    println("Is data_sock open?: ", isopen(data_sock), "green_light: ", green_light)
                end
                # green_light = false
            # end
        end
    # end
# end

@async while isopen(cmd_client)
    write(stdout, readline(cmd_client, keep=true))
end

@async while isopen(data_client)
    data_comm = parse_medipix_communication(data_client)
    while !isempty(data_comm) 
        # write(stdout, readline(cmd_client, keep=true))
        println("Received ", length(data_comm), " bytes.")
    end
end
# @async begin
    # while keep_medipix_servers_on
        # data_sock = accept(data_server)
        @async while isopen(data_sock) && bytesavailable(data_sock) && keep_medipix_servers_on
            open(temp_hdr_path, "w") do output_io
                seekend(output_io)
                # data_to_write = parse_medipix_communication(data_sock)
                data_comm = parse_medipix_communication(data_sock)
                if !isempty(data_comm)
                    write(output_io, String(data_comm))
                end
            end
            open(temp_data_path, "w") do output_io
                seekend(output_io)
                is_mpx, data_comm = parse_medipix_communication(data_sock)
                if is_mpx && !isnothing(data_comm)
                    write(output_io, String(data_comm))
                end
            end
            global green_light = bytesavailable(data_sock) > 0 ? false : true
        end
    # end
# end


write(cmd_client, start_msg)
println(cmd_client, start_msg)
