/*  $Id$

    Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        jan@swi.psy.uva.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 1985-2002, University of Amsterdam

    This program is free software; you can redistribute it and/or
    modify it under the terms of the GNU General Public License
    as published by the Free Software Foundation; either version 2
    of the License, or (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA

    As a special exception, if you link this library with other files,
    compiled with a Free Software compiler, to produce an executable, this
    library does not by itself cause the resulting executable to be covered
    by the GNU General Public License. This exception does not however
    invalidate any other reasons why the executable file might be covered by
    the GNU General Public License.
*/

:- module(test_socket,
	  [ test_socket/0,
	    server/1,			% +Port
	    client/1			% +Address
	  ]).


:- dynamic echo/1, slow/1, quit/1.

:- asserta(user:file_search_path(foreign, '.')).

:- use_module(library(socket)).
%:- use_module(user:socket).		% debugging
%:- use_module(library(streampool)).
%:- use_module('/home/miguel/Desktop/temp/yap-6.3/library/socket.pl').
:- use_module(library(streampool)).

:- use_module(library(debug)).

test_socket :-
	test_udp,
	test_tcp.

test_tcp :-
	make_server(Port, Socket),
	thread_create(run_server(Socket), Server, []),
	client(localhost:Port),
	thread_join(Server, Status),
	(   Status == true
	->  true
	;   format(user_error, 'Server exit-status: ~w~n', [Status]),
	    fail
	).


		 /*******************************
		 *	       SERVER		*
		 *******************************/

server(Port) :-
	make_server(Port, Socket),
	run_server(Socket).

run_server(Socket) :-
	tcp_open_socket(Socket, In, _Out),
	add_stream_to_pool(In, accept(Socket)),
	stream_pool_main_loop.

make_server(Port, Socket) :-
	tcp_socket(Socket),
	tcp_bind(Socket, Port),
	tcp_listen(Socket, 5).

accept(Socket) :-
	tcp_accept(Socket, Slave, Peer),
	debug(connection, 'connect(~p)', [Peer]),
	tcp_open_socket(Slave, In, Out),
	add_stream_to_pool(In, client(In, Out, Peer)).

client(In, Out, Peer) :-
	read(In, Term),
	(   Term == end_of_file
	->  debug(connection, 'close(~p)', [Peer]),
	    close(In),
	    close(Out)
	;   (   catch(action(Term, In, Out), E, true)
	    ->	(   var(E)
		->  true
		;   tcp_send(Out, exception(E))
		)
	    ;	tcp_send(Out, no)
	    )
	).

		 /*******************************
		 *	      ACTION		*
		 *******************************/

action(echo(X), _In, Out) :-
	tcp_send(Out, X).
action(wait(X), _In, Out) :-
	sleep(X),
	tcp_send(Out, yes).
action(slow_read, In, Out) :-
	sleep(2),
	read(In, Term),
	tcp_send(Out, Term).
action(quit, _In, Out) :-
	close_stream_pool,
	tcp_send(Out, quitted).


		 /*******************************
		 *	    CLIENT SIDE		*
		 *******************************/

:- dynamic
	client/2.

client(Address) :-
	tcp_socket(S),
	tcp_connect(S, Address),
	tcp_open_socket(S, In, Out),
	asserta(client(In, Out)),
	test,
	retract(client(In, Out)),
	close(Out),
	close(In).

echo(echo-1) :-
	X = 'Hello World',
	client(In, Out),
	tcp_send(Out, echo(X)),
	tcp_reply(In, X).
echo(echo-2) :-
	findall(A, between(0, 100000, A), X),
	client(In, Out),
	tcp_send(Out, echo(X)),
	tcp_reply(In, X).

slow(slow-1) :-
	client(In, Out),
	tcp_send(Out, wait(2)),
	tcp_reply(In, yes).
slow(slow-1) :-
	client(In, Out),
	tcp_send(Out, slow_read),
	findall(A, between(0, 100000, A), X),
	tcp_send(Out, X),
	tcp_reply(In, X).

quit(quit-1) :-
	client(In, Out),
	tcp_send(Out, quit),
	tcp_reply(In, quitted).


		 /*******************************
		 *	      UTIL		*
		 *******************************/

tcp_send(Out, Term) :-
	format(Out, '~q.~n', [Term]),
	flush_output(Out).

tcp_reply(In, Reply) :-
	read(In, Term),
	reply(Term, In, Reply).

reply(exception(E), _, _) :-
	throw(E).
reply(T, _, T).

		 /*******************************
		 *	       UDP		*
		 *******************************/

receive_loop(Socket, Queue) :-
	repeat,
	    udp_receive(Socket, Data, From, [as(atom)]),
	    thread_send_message(Queue, got(Data, From)),
	    Data == quit, !,
	    tcp_close_socket(Socket).

receiver(Port, ThreadId) :-
	thread_self(Me),
	udp_socket(S),
	tcp_bind(S, Port),
	thread_create(receive_loop(S, Me), ThreadId, []).

test_udp :-
	format(user_error, 'Running test set "udp"', []),
	(   catch(run_udp, E, true)
	->  (   var(E)
	    ->	format(user_error, ' . done~n', [])
	    ;	print_message(error, E)
	    )
	;   format(user_error, 'FAILED~n', [])
	).

run_udp :-
	receiver(Port, ThreadId),
	udp_socket(S),
	udp_send(S, 'hello world', localhost:Port, []),
	thread_get_message(got(X, _)),
	udp_send(S, 'quit', localhost:Port, []),
	thread_get_message(got(Q, _)),
	thread_join(ThreadId, Exit),
	tcp_close_socket(S),
	assertion(X=='hello world'),
	assertion(Q=='quit'),
	assertion(Exit==true), !.


		 /*******************************
		 *        TEST MAIN-LOOP	*
		 *******************************/

testset(echo).
testset(slow).
testset(quit).

:- dynamic
	failed/1,
	blocked/2.

test :-
	retractall(failed(_)),
	retractall(blocked(_,_)),
	forall(testset(Set), runtest(Set)),
	report_blocked,
	report_failed.

report_blocked :-
	findall(Head-Reason, blocked(Head, Reason), L),
	(   L \== []
        ->  format('~nThe following tests are blocked:~n', []),
	    (	member(Head-Reason, L),
		format('    ~p~t~40|~w~n', [Head, Reason]),
		fail
	    ;	true
	    )
        ;   true
	).
report_failed :-
	findall(X, failed(X), L),
	length(L, Len),
	(   Len > 0
        ->  format('~n*** ~w tests failed ***~n', [Len]),
	    fail
        ;   format('~nAll tests passed~n', [])
	).

runtest(Name) :-
	format('Running test set "~w" ', [Name]),
	flush_output,
	functor(Head, Name, 1),
%	nth_clause(Head, _N, R),
	clause( Head, _, R),
	(   catch(Head, Except, true)
	->  (   var(Except)
	    ->  put(.), flush_output
	    ;   Except = blocked(Reason)
	    ->  assert(blocked(Head, Reason)),
		put(!), flush_output
	    ;   test_failed(R, Except)
	    )
	;   test_failed(R, fail)
	),
	fail.
runtest(_) :-
	format(' done.~n').

test_failed(R, Except) :-
	clause(Head, _, R),
	functor(Head, Name, 1),
	arg(1, Head, TestName),
	clause_property(R, line_count(Line)),
	clause_property(R, file(File)),
	(   Except == failed
	->  format('~N~w:~d: Test ~w(~w) failed~n',
		   [File, Line, Name, TestName])
	;   message_to_string(Except, Error),
	    format('~N~w:~d: Test ~w(~w):~n~t~8|ERROR: ~w~n',
		   [File, Line, Name, TestName, Error])
	),
	assert(failed(Head)).

blocked(Reason) :-
	throw(blocked(Reason)).


