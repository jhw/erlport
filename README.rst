ErlPort - connect Erlang to other languages
===========================================

.. contents::

ErlPort is a library for `Erlang <http://erlang.org>`__ which helps connect
Erlang to a number of other programming languages. Currently supported external
languages are `Python 3+ <http://erlport.org/docs/python.html>`__ and `Ruby
1.9+ <http://erlport.org/docs/ruby.html>`__. The library uses `Erlang port protocol
<http://www.erlang.org/doc/reference_manual/ports.html>`__ to simplify
connection between languages and `Erlang external term format
<http://erlang.org/doc/apps/erts/erl_ext_dist.html>`__ to set the common data
types mapping.

**Note:** Python 2 and Ruby 1.8 support has been removed as these versions
are long past their end-of-life dates.

The following is an example ErlPort session for Python:

.. sourcecode:: erl

    1> {ok, P} = python:start().
    {ok,<0.34.0>}
    2> python:call(P, sys, 'version.__str__', []).
    <<"3.10.12 (main, Nov 20 2023, 15:14:05) [GCC 11.4.0]">>
    3> python:call(P, operator, add, [2, 2]).
    4
    4> python:stop(P).
    ok

Check http://erlport.org for more information:

- `ErlPort documentation <http://erlport.org/docs/>`_

  + `Connect Erlang to Python <http://erlport.org/docs/python.html>`_
  + `Connect Erlang to Ruby <http://erlport.org/docs/ruby.html>`_
- `ErlPort downloads <http://erlport.org/downloads/>`_

  + `ErlPort binary packages <http://erlport.org/downloads/#binary-packages>`_
  + `ErlPort source packages <http://erlport.org/downloads/#source-packages>`_

Feedback
--------

Please use Github issues for reporting bugs, offering suggestions or feedback:

- ErlPort issue tracker: https://github.com/erlport/erlport/issues
