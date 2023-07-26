-module(start).

-compile(export_all).
start() ->
    {ok, Pid} = mysql:start_link([{host, "localhost"}, {user, "root"}, {database, "twitter"}]),
    code:add_pathz("").
% include path here
