##
# Example of the socket communications of a peer to peer node.
# Run instances of this script as follows:
#     $ perl p2p.pl [--peer=<PEER_0> --peer=<PEER_1> ... --peer=<PEER_N>] [--host=HOST] [--peer_port=<NUMBER>] [--admin_port=<NUMBER>]
# where <NUMBER> is a valid port number and is unique to each invocation. <PEER_X> should be of the form s.t.u.v:xyz.
# For example: perl p2p.pl --peer_port=7899 --admin_port=9998 --peer=127.0.0.1:7890 --peer=127.0.0.1:7891 --peer=127.0.0.1:7892
# For more details please see http://www.rabbitfarm.com/cgi-bin/blosxom/perl/2022/09/13.
##
package PeerNode{
	use strict;
	use warnings;
	
	use Socket;	
	use boolean;
	use Class::Struct;

	use Data::Dump q/pp/;

	use constant ADMIN_PORT => 9999;
	use constant PEER_CONNECTION_PORT => 7890;
	use constant DEFAULT_HOST => q/localhost/;

	use constant ERROR_OPEN => "Cannot open socket.\n";
	use constant ERROR_BIND => "Cannot bind to port.\n";
	use constant ERROR_LISTEN => "Cannot listen.\n";
	use constant ERROR_CONNECT => "Cannot connect to port.\n";
	use constant ERROR_SET_OPTION => "Cannot set socket option to SO_REUSEADDR.\n";
	
	struct(
	    host => q/$/,
	    admin_port => q/$/,
	    peer_port => q/$/,  
	    peers => q/@/
	);

	sub create_admin_listener{
		my($host, $port) = @_;
		my $admin_socket;
		my $server = $host;
		my $protocol = getprotobyname(q/tcp/);
		socket($admin_socket, PF_INET, SOCK_STREAM, $protocol) or die ERROR_OPEN;
		setsockopt($admin_socket, SOL_SOCKET, SO_REUSEADDR, 1) or die ERROR_SET_OPTION;
		bind($admin_socket, pack_sockaddr_in($port, inet_aton($server))) or die ERROR_BIND;
		listen($admin_socket, 5) or die ERROR_LISTEN;
		return $admin_socket;
	}

	sub create_peer_listener{
		my($host, $port) = @_;
		my $peer_socket;
		my $server = $host;
		my $protocol = getprotobyname(q/tcp/); 
		socket($peer_socket, PF_INET, SOCK_STREAM, $protocol) or die ERROR_OPEN;
		setsockopt($peer_socket, SOL_SOCKET, SO_REUSEADDR, 1) or die ERROR_SET_OPTION;
		bind($peer_socket, pack_sockaddr_in($port, inet_aton($server))) or die ERROR_BIND;
		listen($peer_socket, 5) or die ERROR_LISTEN;
		return $peer_socket;
	}

	sub create_peer_connection{
		my $peer = @_;
		my @peer = split(/:/, $peer);
		my $server = $peer[0] || DEFAULT_HOST;
		my $port = $peer[1] || PEER_CONNECTION_PORT;
		my $peer_socket;
		my $proto = getprotobyname(q/tcp/);
		socket($peer_socket, PF_INET, SOCK_STREAM, (getprotobyname(q/tcp/))[2]) or die ERROR_OPEN;
		connect($peer_socket, pack_sockaddr_in($port, inet_aton($server))) or die ERROR_CONNECT;
		return $peer_socket;
	}

	sub read_socket{
		my($socket_read) = @_;
		my $message = "";
		{
			my $c = getc($socket_read);
			my $done = !defined($c) || $c eq "\n";
			if(!$done){
				$message .= $c if $c;  
			}
			redo unless $done;
		}
		return $message;
	}
	
	sub parse_form{
        my $data = $_[0];
        my %data;
        foreach(split /&/, $data) {
            my ($key, $val) = split /=/;
            $val =~ s/\+/ /g;
            $val =~ s/%(..)/chr(hex($1))/eg;
            $data{$key} = $val;
        }
        return %data;
    }
    
	sub read_admin_socket{
	    my($self, $socket_read) = @_;
	    my %request;
        my $response; 
        local $| = true;
        local $/ = Socket::CRLF;
        while (<$socket_read>) {
            chomp; 
            if(/\s*(\w+)\s*([^\s]+)\s*HTTP\/(\d.\d)/){
                $request{METHOD} = uc $1;
                $request{URL} = $2;
                $request{HTTP_VERSION} = $3;
            } 
            elsif(/:/){
                (my $type, my $val) = split /:/, $_, 2;
                $type =~ s/^\s+//;
                foreach ($type, $val) {
                        s/^\s+//;
                        s/\s+$//;
                }
                $request{lc $type} = $val;
            }
            elsif(/^$/) {
                read($socket_read, $request{CONTENT}, $request{q/content-length/}) if defined $request{q/content-length/};
                last;
            }
        }
        if($request{METHOD} eq q/GET/){
            if ($request{URL} =~ /(.*)\?(.*)/){
                $request{URL} = $1;
                $request{CONTENT} = $2;
                $request{DATA} = parse_form($request{CONTENT});
            } 
        } 
        elsif($request{METHOD} eq q/POST/){
            $request{DATA} = parse_form($request{CONTENT});    
        } 
        $response .=  q#HTTP/1.0 200 OK# . Socket::CRLF;
        $response .=  q#Content-type: text/html# . Socket::CRLF;
        $response .=  Socket::CRLF;
        if($request{METHOD} eq q/GET/ && $request{URL} eq q#/peers#){
            $response .= join(Socket::CRLF, @{$self->peers()});
        }
        print $response;
        syswrite $socket_read, $response;
        close($socket_read);
	}
	
	sub run{
	    my $self = shift; 
	    my $admin_socket = create_admin_listener($self->host(), $self->admin_port());
        my $peer_listener_socket = create_peer_listener($self->host(), $self->peer_port());
        my @peer_connections;
        my $ready = q//;
		vec($ready, fileno($admin_socket), 1) = 1;
		vec($ready, fileno($peer_listener_socket), 1) = 1; 
        for my $peer (@{$self->peers()}){
            my $peer_socket = create_peer_connection($peer);
            push @peer_connections, $peer_socket;
            vec($ready, fileno($peer_socket), 1) = 1;
        }
		my @connections;
		my @admin_connections;
		while(true){
			my $message = "";
			select($ready, undef, undef, undef);
			##
		    # 1. Check which connections are ready.
		    ##
			for my $peer_connection_socket (@peer_connections){
			    if(vec($ready, fileno($peer_connection_socket), 1)){
				    accept(my $peer_connection_socket_read, $peer_connection_socket);
				    $connections[fileno($peer_connection_socket_read)] = $peer_connection_socket_read;
				    vec($ready, fileno($peer_connection_socket_read), 1) = 1;
			    }
			}
			if(vec($ready, fileno($admin_socket), 1)){
				accept(my $admin_socket_read, $admin_socket);
				#$connections[fileno($admin_socket_read)] = $admin_socket_read;
				push @admin_connections, $admin_socket_read;
				#vec($ready, fileno($admin_socket_read), 1) = 1;
			}			
			if(vec($ready, fileno($peer_listener_socket), 1)){
				accept(my $peer_listener_socket_read, $peer_listener_socket);
				$connections[fileno($peer_listener_socket_read)] = $peer_listener_socket_read;
				vec($ready, fileno($peer_listener_socket_read), 1) = 1;
			}
			##
			# 2. For all the ready connections receive/respond to messages.
			##
			for my $connection (@admin_connections){
			    $self->read_admin_socket($connection);
			    #vec($ready, fileno($connection), 1) = 1 if $connection;
			}
			for my $connection (@connections){
				if($connection && vec($ready, fileno($connection), 1)){
					my $message;
					$message = read_socket($connection);# unless grep {$_ == $connection} @admin_connections;
					#$message = $self->read_admin_socket($connection) if grep {$_ == $connection} @admin_connections;
					syswrite $connection, "Thanks for the message: $message\n";
				}
				vec($ready, fileno($connection), 1) = 1 if $connection;
				#else{
				#    delete from @connections? Just leave alone and it'll eventually get overwritten?
				#}
			}
			##
			# 3. Reset bit vectors.
			##
			vec($ready, fileno($admin_socket), 1) = 1;
			vec($ready, fileno($peer_listener_socket), 1) = 1;
            for my $peer_connection_socket (@peer_connections){
                vec($ready, fileno($peer_connection_socket), 1) = 1;
            }
            @admin_connections = ();
		}
	}
	true;
}

package main{
    use Getopt::Long;
   
    my $host = PeerNode::DEFAULT_HOST;
    my $admin_port = PeerNode::ADMIN_PORT;
    my $peer_port = PeerNode::PEER_CONNECTION_PORT;
    my $peers;
    GetOptions("host=i" => \$host);
    GetOptions("admin_port=i" => \$admin_port);
    GetOptions("peer_port=i" => \$peer_port);
    GetOptions("peer=s@" => \$peers); 
    
    my $peer_node = new PeerNode(host => $host, admin_port => $admin_port, peer_port => $peer_port, peers => @{$peers});
    $peer_node->run();
}