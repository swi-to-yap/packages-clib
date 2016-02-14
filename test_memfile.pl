/*  Part of SWI-Prolog

    Author:        Jan Wielemaker
    E-mail:        J.Wielemaker@vu.nl
    WWW:           http://www.swi-prolog.org
    Copyright (C): 1985-2014, University of Amsterdam,
			      VU University Amsterdam

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

:- module(test_memfile,
	  [ test_memfile/0
	  ]).
:- asserta(user:file_search_path(foreign, '.')).
:- asserta(user:file_search_path(library, '../plunit')).

:- use_module(library(lists)).
:- use_module(library(shlib)).

:- use_module(memfile).
:- use_module(library(utf8)).
:- use_module(library(plunit)).
:- use_module(library(debug)).

test_memfile :-
	run_tests([ mf_write,
		    mf_update,
		    mf_atom,
		    mf_position,
		    mf_encoding
		  ]).


:- begin_tests(mf_write).

wr_atom(Atom, A2) :-
	new_memory_file(H),
	setup_call_cleanup(
	    open_memory_file(H, write, Out),
	    write(Out, Atom),
	    close(Out)),
	memory_file_to_atom(H, A2),
	size_memory_file(H, Size),
	atom_length(Atom, Size),
	A2 == Atom.

test(simple, Atom == Atom2) :-
	Atom = 'Hello World',
	wr_atom(Atom, Atom2).
test(wide, Atom == Atom2) :-
	atom_codes(Atom, [97,98,1080,1081]),
	wr_atom(Atom, Atom2).

:- end_tests(mf_write).

:- begin_tests(mf_update).

test(append, cleanup(free_memory_file(MF))) :-
	mf_format(MF, write, 'Hello world!', []),
	assertion(memory_file_to_codes(MF, `Hello world!`)),
	mf_format(MF, append, '\n', []),
	assertion(memory_file_to_codes(MF, `Hello world!\n`)).
test(insert_start, cleanup(free_memory_file(MF))) :-
	mf_format(MF, write, 'Hello world!', []),
	assertion(memory_file_to_codes(MF, `Hello world!`)),
	mf_format(MF, insert, '\n', []),
	memory_file_to_codes(MF, Codes),
	assertion(Codes == `\nHello world!`).
test(insert_middle, cleanup(free_memory_file(MF))) :-
	mf_format(MF, write, 'Hello world!', []),
	assertion(memory_file_to_codes(MF, `Hello world!`)),
	mf_format(MF, insert, '\n', []),
	mf_format(MF, insert(7), 'nice ', []),
	memory_file_to_codes(MF, Codes),
	assertion(Codes == `\nHello nice world!`).
test(update_middle, cleanup(free_memory_file(MF))) :-
	mf_format(MF, write, 'Hello world!', []),
	assertion(memory_file_to_codes(MF, `Hello world!`)),
	mf_format(MF, insert, '\n', []),
	mf_format(MF, insert(7), 'nice ', []),
	mf_format(MF, update(7), 'NICE ', []),
	memory_file_to_codes(MF, Codes),
	assertion(Codes == `\nHello NICE world!`).
test(insert, cleanup(free_memory_file(MF))) :-
	new_memory_file(MF),
	insert_memory_file(MF, 0, abc),
	memory_file_to_codes(MF, Codes),
	assertion(Codes == `abc`).
test(insert, cleanup(free_memory_file(MF))) :-
	new_memory_file(MF),
	insert_memory_file(MF, 0, 'hello(world).\n'),
	setup_call_cleanup(
	    open_memory_file(MF, read, In),
	    read(In, Term),
	    close(In)),
	assertion(Term == hello(world)),
	setup_call_cleanup(
	    open_memory_file(MF, read, In2),
	    read(In2, Term2),
	    close(In2)),
	assertion(Term2 == hello(world)).
test(insert, cleanup(free_memory_file(MF))) :-
	new_memory_file(MF),
	insert_memory_file(MF, 0, '0123456789'),
	memory_file_substring(MF, 1, 2, A1, "12"),
	assertion(A1 == 7),
	memory_file_substring(MF, 4, 5, A2, S2),
	assertion(A2-S2 == 1-"45678").

:- end_tests(mf_update).


:- begin_tests(mf_atom).

rd_atom(Atom, Atom2) :-
	atom_to_memory_file(Atom, File),
	open_memory_file(File, read, In),
	read_to_codes(In, Codes),
	close(In),
	atom_codes(Atom2, Codes).

read_to_codes(In, Codes) :-
	get_code(In, C0),
	read_to_codes(C0, In, Codes).

read_to_codes(-1, _, []) :- !.
read_to_codes(C0, In, [C0|T]) :-
	get_code(In, C1),
	read_to_codes(C1, In, T).

test(simple, Atom == Atom2) :-
	Atom = 'Hello World',
	rd_atom(Atom, Atom2).
test(wide, Atom == Atom2) :-
	atom_codes(Atom, [97,98,1080,1081]),
	rd_atom(Atom, Atom2).

:- end_tests(mf_atom).

:- begin_tests(mf_position).

test(pos) :-
	new_memory_file(MF),
	open_memory_file(MF, write, Out),
	format(Out, '~s', [[97, 254, 500]]),
	close(Out),
	size_memory_file(MF, CodeSize),
	open_memory_file(MF, read, In),
	get_code(In, _),
	get_code(In, _),
	utf8_position_memory_file(MF, Here, Size),
	close(In),
	assertion(CodeSize == 3),	% size in characters
	assertion(Here == 3),
	assertion(Size == 5).
test(line, cleanup(free_memory_file(MF))) :-
	mf_format(MF, write, '1-0123456789\n2-0123456789', []),
	memory_file_line_position(MF, 1, 4, Offset1),
	assertion(Offset1 == 4),
	memory_file_line_position(MF, Line1, Pos1, Offset1),
	assertion(Line1:Pos1 == 1:4),
	memory_file_line_position(MF, 2, 4, Offset2),
	assertion(Offset2 == 17),
	memory_file_line_position(MF, Line2, Pos2, Offset2),
	assertion(Line2:Pos2 == 2:4),
	assertion(\+ memory_file_line_position(MF, 3, 4, _)),
	size_memory_file(MF, Size),
	memory_file_line_position(MF, Line3, Pos3, Size),
	assertion(Line3:Pos3 == 2:12),
	SizeOne is Size+1,
	assertion(\+ memory_file_line_position(MF, _, _, SizeOne)).
test(empty, cleanup(free_memory_file(MF))) :-
	new_memory_file(MF),
	memory_file_line_position(MF, 1, 0, Pos),
	assertion(Pos == 0),
	memory_file_line_position(MF, Line, LinePos, 0),
	assertion(Line:LinePos == 1:0).
test(end_no_nl, cleanup(free_memory_file(MF))) :-
	mf_format(MF, write, '123', []),
	memory_file_line_position(MF, 1, 3, Pos),
	assertion(Pos == 3),
	memory_file_line_position(MF, Line, LinePos, 3),
	assertion(Line:LinePos == 1:3).


:- end_tests(mf_position).

:- begin_tests(mf_encoding).

test(enc1, String == String2) :-	% Encode to UTF-8
	String = [97, 254, 500],
	new_memory_file(MF),
	open_memory_file(MF, write, Out, [encoding(utf8)]),
	format(Out, '~s', [String]),
	close(Out),
	open_memory_file(MF, read, In, [encoding(octet)]),
	read_stream_to_codes(In, Codes),
	close(In),
	free_memory_file(MF),
	phrase(utf8_codes(String2), Codes).
test(enc2) :-
	String = [97, 254, 500],
	new_memory_file(MF),
	open_memory_file(MF, write, Out, [encoding(utf8)]),
	format(Out, '~s', [String]),
	close(Out),
	size_memory_file(MF, Size, octet),
	phrase(utf8_codes(String), Codes),
	assertion(length(Codes, Size)).

:- end_tests(mf_encoding).

		 /*******************************
		 *	     UTILITIES		*
		 *******************************/

%%	mf_format(?MF, +Open, +Format, +Args)
%
%	Create or reuse an MF.  Open  it   in  a  mode, where insert and
%	update  allow  for  insert(Offset)    and  update(Offset).  Call
%	format/3 and close MF.

<<<<<<< HEAD
:- dynamic
	failed/1,
	blocked/2.

test_memfile :-
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
	nth_clause(Head, _N, R),
	clause(Head, _, R),
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
	clause(ClHead, _, R),
	plain_head(ClHead, Head),
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
=======
mf_format(MF, Open, Fmt, Args) :-
	(   var(MF)
	->  new_memory_file(MF)
	;   true
>>>>>>> 47df40fe09ec8bb62b42e9e840a257e7315e3bff
	),
	setup_call_cleanup(
	    open_mf(MF, Open, Out),
	    format(Out, Fmt, Args),
	    close(Out)).

open_mf(MF, insert(Pos), Out) :- !,
	open_memory_file(MF, insert, Out),
	seek(Out, Pos, bof, _).
open_mf(MF, update(Pos), Out) :- !,
	open_memory_file(MF, update, Out),
	seek(Out, Pos, bof, _).
open_mf(MF, How, Out) :-
	open_memory_file(MF, How, Out).

