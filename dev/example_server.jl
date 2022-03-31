# context: http://stackoverflow.com/questions/39448808/julia-tcp-server-and-connection

# Use fn to process messages from sock.
# Loop till sock is open and fn returns true.
function processor(fn, sock)
    proc = true
    try
        while proc && ((nb_available(sock) > 0) || isopen(sock))
            proc = fn(sock)
        end
    catch ex
        # We don't have any shutdown message.
        # EOFErrors are expected when connections are closed
        isa(ex, EOFError) || rethrow(ex)
    finally
        close(sock)
    end
end

# Listen for connections on port.
# Process connections with fn.
# If async, start a separate task for each connection.
# Else, process connections serially.
function server(fn, port, async)
    listen_sock = listen(port)
    println("listening on port $port")

    if async
        while isopen(listen_sock)
            sock = accept(listen_sock)
            println("starting processor task")
            @async processor(fn, sock)
        end
    else
        sock = accept(listen_sock)
        println("processing connection")
        processor(fn, sock)
        close(listen_sock)
    end
end

# my server 2
function myserver2(port)
    nmsgs = 0
    server(port, false) do conn
        # read msg and do something with it
        msg = round(read(conn, Float64, 140), 3)
        mat = reshape(msg[1:140], 10, 14)
        # print activity indicator
        nmsgs += 1
        if (nmsgs % 100) == 0
            print('.')
        end
        true
    end
end

# my server 1
function myserver1(port, server2_port)
    chan = Channel{Vector{Float64}}(typemax(Int))
    interval = 0.01
    message  = zeros(10, 14)

    # an async server reads incoming messages and puts them into chan
    @async server(port, true) do conn
        put!(chan, read(conn, Float64, 11))
        true
    end

    # continue till server 2 is up
    s2conn = connect(server2_port)
    while isopen(s2conn)
        nupdates = 0
        # if we have messages in chan, use them to update the data we send to server 2.
        # don't wait if there are none.
        while isready(chan)
            update = take!(chan)
            message[:,convert(Int64,update[1])] = update[2:11]
            nupdates += 1
        end
        if nupdates > 0
            println("assimilated $nupdates updates.")
        end

        # write latest data to server 2 at the desired regular interval
        write(s2conn, reshape(message, 140))
        sleep(interval)
    end
end

# send data to my server 1
function senddata(port, msg, n=1)
    s1conn = connect(port)
    for x in 1:n
        write(s1conn, msg)
    end
    close(s1conn)
end