# Perl peer-to-peer (p2p.pl) - an example p2p node in Perl

### Motivation
When studying decentralized applications, distributed ledgers (e.g. blockchains), and digital currencies you
quickly get an appreciation for the underlying peer to peer communications required. This example peer node
strips away everything except the fundamental necessities of peer to peer networking.
 
### Key concepts 
Also see [this blog post](http://www.rabbitfarm.com/cgi-bin/blosxom/perl/2022/09/17) for a more detailed overview of the key concepts and in depth review of the code.
* HTTP interface to list/add/delete peer nodes
* Low level Socket primitives are used to provide a familiar set of API calls for those looking to implement these concepts in C and C++. Almost all languages will hace similar networking functions available. In this way, Perl is acting as a rapid prototyping language, a function at which it excels.
* Nodes send each only one kind of message. This one message type is for adding two numbers.
* There is some error handling but to maintain simplicity more advanced error handling is not implemented. For example, this code would be more robust if PIPE signals were handled if an attempt was made to write to a closed socket. 

### Quick start
(Set up two connected nodes on the same system. Use two terminal windows.)

Terminal Window A
```
$ perl p2p.pl --host=127.0.0.1  --peer_port=7899 --admin_port=9998

```

Terminal Window B
```
$ perl p2p.pl --host=127.0.0.1  --peer_port=7898 --admin_port=9997 --peer=127.0.0.1:7899

```

### HTTP API
##### Get peers
```
wget http://localhost:9998/peers
```
##### Add peer
```
wget --post-data="peer=127.0.0.1:7898" http://localhost:9998/addPeer
```
##### Delete peer
```
wget --post-data="peer=127.0.0.1:7898" http://localhost:9998/deletePeer
```
