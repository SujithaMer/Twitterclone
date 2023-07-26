-module(server).

-compile(nowarn_export_all).
-compile(export_all).

start() ->
    register(server, self()),
    code:add_pathz("../rebar3/_build/default/lib/mysql/ebin"),
    UserLogIns = dict:new(),
    start(UserLogIns, []).

start(LoggedIn, Threads) ->
    receive
        % A server spawn has finished work, reduce number of allocated threads.
        {'DOWN', _, process, Pid2, thread_complete} ->
            NewThreads = lists:delete(Pid2, Threads),
            start(LoggedIn, NewThreads);

        {'DOWN', _, process, Pid2, _} ->
            Username = get(Pid2),
            erase(Pid2),
            NewLoggedIn = dict:erase(Username, LoggedIn),
            start(NewLoggedIn, Threads);

        % Client Request To Register a user
        {client_register, ClientPid, Username, Password} ->
            io:fwrite("recieved client_register\n"),
            if (length(Threads) == 10) ->
                Pid2 = server_wait(),
                NewThreads = lists:delete(Pid2, Threads);
            true ->
                NewThreads = Threads
            end,
            Line=ClientPid+" "+Username+" "+Password,
            SpawnThread = spawn(server, register_user_start_json, [Line]),
            monitor(process, SpawnThread),
            start(LoggedIn, NewThreads ++ [SpawnThread]);

        % Server thread response to register request
        {server_register, Status, Username, ClientPid} ->
            io:fwrite("recieved server_register\n"),
            if Status == error ->
                ClientPid ! {register_response, error},
                NewLoggedIn = LoggedIn;
            true ->
                ClientPid ! {register_response, Username, ok},
                monitor(process, ClientPid),
                NewLoggedIn = dict:store(Username, ClientPid, LoggedIn),
                put(ClientPid, Username)
            end,
            start(NewLoggedIn, Threads);

        % Client Login Request
        {client_login, ClientPid, Username, Password} ->
            io:fwrite("recieved client_login\n"),
            if (length(Threads) == 10) ->
                Pid2 = server_wait(),
                NewThreads = lists:delete(Pid2, Threads);
            true ->
                NewThreads = Threads
            end,
            SpawnThread = spawn(server, login_user, [ClientPid, Username, Password]),
            monitor(process, SpawnThread),
            start(LoggedIn, NewThreads ++ [SpawnThread]);

        % Server thread response to Login Request
        {server_login, Status, Username, ClientPid} ->
            io:fwrite("recieved server_login\n"),
            if Status == error ->
                ClientPid ! {login_response, error},
                NewLoggedIn = LoggedIn;
            true ->
                ClientPid ! {login_response, Username, ok},
                monitor(process, ClientPid),
                NewLoggedIn = dict:store(Username, ClientPid, LoggedIn),
                put(ClientPid, Username)
            end,
            start(NewLoggedIn, Threads);


        % Client Tweet Request
        {client_tweet, Username, Tweet} ->
            io:fwrite("recieved client_tweet\n"),
            if (length(Threads) == 10) ->
                Pid2 = server_wait(),
                NewThreads = lists:delete(Pid2, Threads);
            true ->
                NewThreads = Threads
            end,
            SpawnThread = spawn(server, client_tweet, [Username, Tweet]),
            monitor(process, SpawnThread),
            start(LoggedIn, NewThreads ++ [SpawnThread]);

        % Server response to Tweet Request
        {server_tweet, Status, Username, FinalUsers, Tweet, TweetId} ->
            io:fwrite("recieved server_tweet\n"),
            case dict:find(Username, LoggedIn) of
                {ok, ClientPid} ->
                    if Status == error ->
                        ClientPid ! {tweet_response, error};
                    true ->
                        ClientPid ! {tweet_response, ok}
                    end;
                error ->
                    ok
            end,
            spawn(server, send_tweets, [Tweet, FinalUsers, LoggedIn, Username, TweetId]),
            start(LoggedIn, Threads);

        % Client wants to subscribe to something
        {client_subscribe_to, Username, Name} ->
            io:fwrite("recieved client_subscribe_to\n"),
            if (length(Threads) == 10) ->
                Pid2 = server_wait(),
                NewThreads = lists:delete(Pid2, Threads);
            true ->
                NewThreads = Threads
            end,
            SpawnThread = spawn(server, subscribe_to, [Username, Name]),
            monitor(process, SpawnThread),
            start(LoggedIn, NewThreads ++ [SpawnThread]);

        % Client wants to query to something
        {client_query, Username, Name} ->
            io:fwrite("recieved client_query\n"),
            if (length(Threads) == 10) ->
                Pid2 = server_wait(),
                NewThreads = lists:delete(Pid2, Threads);
            true ->
                NewThreads = Threads
            end,
            SpawnThread = spawn(server, query_tweets, [Username, Name]),
            monitor(process, SpawnThread),
            start(LoggedIn, NewThreads ++ [SpawnThread]);

        % Server response to client query to something
        {server_query, Username, Tweet, TweetId, Tweeter} ->
            io:fwrite("recieved server_query\n"),
            case dict:find(Username, LoggedIn) of
                {ok, ClientPid} ->
                        ClientPid ! {query_response, Tweet, TweetId, Tweeter};
                error ->
                    ok  
            end,
            start(LoggedIn, Threads);

        % Client wants to retweet. Response in server_tweet
        {client_retweet, Username, TweetId} ->
            io:fwrite("recieved client_retweet\n"),
            if (length(Threads) == 10) ->
                Pid2 = server_wait(),
                NewThreads = lists:delete(Pid2, Threads);
            true ->
                NewThreads = Threads
            end,
            SpawnThread = spawn(server, retweet, [Username, TweetId]),
            monitor(process, SpawnThread),
            start(LoggedIn, NewThreads ++ [SpawnThread])
    end.

% Server is waiting for a thread to finish
server_wait() ->
    receive
        {'DOWN', _, process, Pid2, thread_complete} ->
            Pid2
    end.

% APIS

% API to check for tweets
check_for_tweets()->ok.
% check_for_tweets_handle('GET', _Arg) ->
%     io:format("~n ~p:~p GET Request ~n", [?MODULE, ?LINE]),
%     Records = query_tweets(qlc:q([X || X <- mnesia:table(Users)])),
%     Json = convert_to_json( Records),
%     io:format("~n ~p:~p GET Request Response ~p ~n", [?MODULE, ?LINE, Json]),
%     {html, Json}.

% API to registers a user
register_user_start_json(Lines,register)->
    Username=Lines,
    Data=[{obj,[{username, Line},
    {password, Line}]}|| Line<-Lines],
    % Check if the username is already available in the database
    Check=check_if_username_already_used(Username),
    JsonData={obj,[{data, Data,Check}]},
    register_user_handle('POST',JsonData),
    rfc:encode().

register_user_handle('POST', Arg) ->
    {ok, Json, _} = rfc4627:decode(Arg),
    io:format("~n~p:~p POST request ~p~n", 
              [?MODULE, ?LINE, Json]),
    User = rfc4627:get_field(Json, "username", <<>>),
    Password	= rfc4627:get_field(Json, "passowrd", <<>>),
    [{status, 200},
    register_user(self(),User,Password),
     {html, Arg}].

% API to search for tweets
check_for_user_tweets_json_hashtag(Lines,register)->
    Username=Lines,
    Data=[{obj,[{username, Line},
    {userid, Line},
    {hashtag},{tweetid,Line,'tweet'}]}|| Line<-Lines],
    % Check if the username is already available in the database
    check_if_username_already_used(Username),
    JsonData={obj,[{data, Data}]},
    register_user_handle('POST',JsonData),
    rfc:encode().

check_for_user_tweets_json_mentions(Lines,register)->
    Username=Lines,
    Data=[{obj,[{username, Line},
    {userid, Line},
    {mention}]}|| Line<-Lines],
    % Check if the username is already available in the database
    check_if_username_already_used(Username),
    JsonData={obj,[{data, Data}]},
    register_user_handle('POST',JsonData),
    rfc:encode().

check_for_user_tweets_handle('POST', Arg) ->
    {ok, Json, _} = rfc4627:decode(Arg),
    io:format("~n~p:~p POST request ~p~n", 
              [?MODULE, ?LINE, Json]),
    User = rfc4627:get_field(Json, "username", <<>>),
    Password	= rfc4627:get_field(Json, "passowrd", <<>>),
    [{status, 200},
    register_user(self(),User,Password),
     {html, Arg}].

check_if_username_already_used(Username)->
    % Call the username checking API to check if the username is already available in the database
check_username_usage_handle('POST',Username).
    
check_username_usage_handle('POST',Username)->
    Method='POST',
    {ok, Json, _} = rfc4627:decode(Method),
    io:format("~n~p:~p POST request ~p~n", 
              [?MODULE, ?LINE, Json]),
    Username = rfc4627:get_field(Json, "username", <<>>),
    Arg=handle(Method,check),
    check_username_db(self(),Username),
    receive
        {exists,UsernameAlreadyExists}->io:fwrite(UsernameAlreadyExists)
    end,
    Status=[{status, 200},
     {html, Arg}
     ],
     io:fwrite(Status).

check_username_db(ClientPid, Username) ->
    {ok, Pid} = mysql:start_link([{host, "localhost"}, {user, "root"}, {database, "twitterDB"}]),
    {ok, _, Res0} = mysql:query(Pid, "SHOW TABLES LIKE 'Users';"),
    if length(Res0) == 0 ->
        ok = mysql:query(Pid, "CREATE TABLE Users (
            username varchar(255) UNIQUE,
            password varchar(255)
        );");
    true ->
        ok
    end,
    if length(Res0) >= 0 ->
        server ! {server_register, ok, Username, ClientPid},
        UsernameExists= string:concat(string:concat("SELECT * FROM Users where username like", Username)),
        server ! {server_register, error, Username, ClientPid}
    end,
        ClientPid ! {exists,UsernameExists},
    mysql:stop(Pid),
    exit(thread_complete).

% API to Login a User
login_user_start_json(Lines,register)->
    Username=Lines,
    Data=[{obj,[{username, Line},
    {userid, Line},
    {hashtag}]}|| Line<-Lines],
    % Check if the username is already available in the database
    check_if_username_already_used(Username),
    JsonData={obj,[{data, Data}]},
    login_user_handle('POST',JsonData),
    rfc:encode().

login_user_handle('POST', Arg) ->
    Method='POST',
    {ok, Json, _} = rfc4627:decode(Arg),
    io:format("~n~p:~p POST request ~p~n", 
              [?MODULE, ?LINE, Json]),
    User = rfc4627:get_field(Json, "username", <<>>),
    Password	= rfc4627:get_field(Json, "passowrd", <<>>),
    handle(Method,check),
    Status=[{status, 200},
     {html, Arg}
     ],
     io:format(Status,User,Password).

% API to perform a query
query_user_start_json(Lines,register)->
    Username=Lines,
    Data=[{obj,[{username, Line},
    {userid, Line},
    {hashtag},{query}]}|| Line<-Lines],
    % Check if the username is already available in the database
    check_if_username_already_used(Username),
    JsonData={obj,[{data, Data}]},
    login_user_handle('POST',JsonData),
    rfc:encode().

query_user_handle('POST', Arg) ->
    Method='POST',
    {ok, Json, _} = rfc4627:decode(Arg),
    io:format("~n~p:~p POST request ~p~n", 
              [?MODULE, ?LINE, Json]),
    User = rfc4627:get_field(Json, "username", <<>>),
    handle(Method,check),
    Status=[{status, 200},
     {html, Arg}
     ],
     io:format(Status,User).

% API to delete a user
delete_user_start_json(Lines,register)->
    Username=Lines,
    Data=[{obj,[{username, Line},
    {password, Line}]}|| Line<-Lines],
    % Check if the username is available in the database
    Check=check_if_username_already_used(Username),
    if 
        Check -> ok
    end,
    JsonData={obj,[{data, Data,Check}]},
    delete_user_handle('DELETE',JsonData),
    rfc:encode().

delete_user_handle('DELETE', Arg) ->
    {ok, Json, _} = rfc4627:decode(Arg),
    io:format("~n~p:~p POST request ~p~n", 
              [?MODULE, ?LINE, Json]),
    User = rfc4627:get_field(Json, "username", <<>>),
    Status=[{status, 200},
     {html, Arg}],
     io:fwrite(Status),
     delete_user(self(),User).

delete_user(ClientPid,Userid)->{ok, Pid} = mysql:start_link([{host, "localhost"}, {user, "root"}, {database, "twitterDB"}]),
{ok, _, Res0} = mysql:query(Pid, "SHOW TABLES LIKE 'Users';"),
if length(Res0) == 0 ->
    ok = mysql:query(Pid, "CREATE TABLE Users (
        username varchar(255) UNIQUE,
        password varchar(255)
    );");
true ->
    ok
end,
Res1=mysql:query(Pid, "DELETE FROM Users WHERE username = ?;", [Userid]),
io:fwrite(ClientPid,Userid,Res1).



register_user(ClientPid, Username, Password) ->
    {ok, Pid} = mysql:start_link([{host, "localhost"}, {user, "root"}, {database, "twitterDB"}]),
    {ok, _, Res0} = mysql:query(Pid, "SHOW TABLES LIKE 'Users';"),
    if length(Res0) == 0 ->
        ok = mysql:query(Pid, "CREATE TABLE Users (
            username varchar(255) UNIQUE,
            password varchar(255)
        );");
    true ->
        ok
    end,
    Res1 = mysql:query(Pid, "INSERT INTO Users VALUES (?, ?);", [Username, Password]),
    if Res1 == ok ->
        server ! {server_register, ok, Username, ClientPid},
        UsernameSub = string:concat(Username, "_subscribers"),
        UsernameTo = string:concat(Username, "_subscribed_to"),
        UsernameSubQuery = string:concat(string:concat("CREATE TABLE ", UsernameSub), " (username varchar(255) UNIQUE);"),
        UsernameToQuery = string:concat(string:concat("CREATE TABLE ", UsernameTo), " (name varchar(255) UNIQUE, tweetID INT);"),
        ok = mysql:query(Pid, UsernameSubQuery),
        ok = mysql:query(Pid, UsernameToQuery);
    true ->
        server ! {server_register, error, Username, ClientPid}
    end,
    mysql:stop(Pid),
    exit(thread_complete).

handle(Method,_) ->
    [{error, "Unknown method " ++ Method},
     {status, 405},
     {header, "Allow: GET, HEAD, POST, PUT, DELETE"}
     ].

accept_only_format(Format, Headers) ->
    Res = lists:any(fun (F) ->
		      string:equal(Format, F) 
	      end, Headers),
          io:fwrite(Res).

request_only_format(Arg) ->
    Rec    = Arg,
    Accept = Rec,
    [AcceptFormats| _]  = string:tokens(Accept, ";"),
    string:tokens(AcceptFormats, ",").

login_user(ClientPid, Username, Password) ->
    {ok, Pid} = mysql:start_link([{host, "localhost"}, {user, "root"}, {database, "twitterDB"}]),
    {ok, _, Res0} = mysql:query(Pid, "SHOW TABLES LIKE 'Users';"),
    if length(Res0) == 0 ->
        server ! {server_login, error, Username, ClientPid};
    true ->
        {ok, _, StoredPasswordList} = mysql:query(Pid, "SELECT password from Users WHERE username = ?;", [Username]),
        if length(StoredPasswordList) == 0 ->
            server ! {server_login, error, Username, ClientPid};
        true ->
            StoredPassword = lists:nth(1, lists:nth(1, StoredPasswordList)),
            StringStoredPassword = binary_to_list(StoredPassword),
            if StringStoredPassword == Password ->
                server ! {server_login, ok, Username, ClientPid};
            true ->
                server ! {server_login, error, Username, ClientPid}
            end
        end
    end,
    mysql:stop(Pid),
    exit(thread_complete).

client_tweet(Username, Tweet) ->
    % Uses MySQL to store the data 
    % Establish connection with the database
    {ok, Pid} = mysql:start_link([{host, "localhost"}, {user, "root"}, {database, "twitterDB"}]),
    % Check if the table already exists. If not, create to store all the tweets sent by the users
    {ok, _, Query1} = mysql:query(Pid, "SHOW TABLES LIKE 'tblUserTweets';"),
    if length(Query1) == 0 ->
        ok = mysql:query(Pid, "CREATE TABLE tblUserTweets (
            tweetID INT AUTO_INCREMENT,
            username varchar(255),
            tweets TEXT,
            primary key (tweetID)
        );");
    true ->
        ok
    end,
    % Insert the tweet into the table tblUserTweets
    Query2 = mysql:query(Pid, "INSERT INTO tblUserTweets (username, tweet) VALUES (?, ?);", [Username, Tweet]),
    if Query2 /= ok ->
        server ! {server_tweet, error, Username, error, error, error};
    true ->
        TweetId = mysql:insert_id(Pid),
        Users = process_tweet(Tweet, TweetId, Pid),
        Subscribers = string:concat(Username, "_subscribers"),
        SelectQuery = string:concat(string:concat("SELECT * from ", Subscribers), ";"),
        {ok, _, Res2} = mysql:query(Pid, SelectQuery),
        FinalUsers = sets:to_list(sets:from_list(Users ++ Res2)),
        server ! {server_tweet, ok, Username, FinalUsers, Tweet, TweetId}
    end,
    mysql:stop(Pid),
    exit(thread_complete).

process_tweet(Tweet, TweetId, Pid) ->
    ModifiedTweet = string:chomp(string:concat(Tweet," ")),
    % check if the tweet has any mentions, if yes add it to the mentioned bucket
    case re:run(ModifiedTweet, "@[^ ]*", [global]) of
        {match, Mention} ->
            MentiondUsers = dump_tweet_into_bucket_selected(Tweet, TweetId, Mention, Pid);
        nomatch ->
            MentiondUsers = []
    end,
    % check if the new tweet has any hastags, if yes add it to the mentioned bucket
    case re:run(ModifiedTweet, "#[^ ]*", [global]) of
        {match, Hashtag} ->
            HashTagFollowers = dump_tweet_into_bucket(Tweet, TweetId, Hashtag, Pid);
        nomatch ->
            HashTagFollowers = []
    end,
    HashTagFollowers ++ MentiondUsers.

dump_tweet_into_bucket(_, _, [], _) ->
    [];
dump_tweet_into_bucket(Tweet, TweetId, HashCaptured, Pid) ->
    [HashValue | RemainingValue] = HashCaptured,
    {Start, Length} = lists:nth(1, HashValue),
    HashString = string:slice(Tweet, Start, Length),
    StringWithoutHash = string:prefix(HashString, "#"),
    FinalString =  string:concat("hash_", StringWithoutHash),
    FinalStringUsers = string:concat(FinalString, "_users"),
    ShowQuery = string:concat(string:concat("SHOW TABLES LIKE '", FinalString), "';"),
    {ok, _, Res0} = mysql:query(Pid, ShowQuery),
    if length(Res0) == 0 ->
        FinalStringQuery = string:concat(string:concat("CREATE TABLE ", FinalString), " (tweetID INT);"),
        FinalStringUsersQuery = string:concat(string:concat("CREATE TABLE ", FinalStringUsers), " (username varchar(255) UNIQUE);"),
        ok = mysql:query(Pid, FinalStringQuery),
        ok = mysql:query(Pid, FinalStringUsersQuery);
    true ->
        ok
    end,
    InsertQuery = string:concat(string:concat("INSERT INTO ", FinalString), " VALUES (?);"),
    ok = mysql:query(Pid, InsertQuery, [TweetId]),
    SelectQuery = string:concat(string:concat("SELECT * from ", FinalStringUsers), ";"),
    case mysql:query(Pid, SelectQuery) of
        {ok, _, Res2} ->
            ok;
        {error, _} ->
            Res2 = []
    end,
    Res2 ++ dump_tweet_into_bucket(Tweet, TweetId, RemainingValue, Pid).

dump_tweet_into_bucket_selected(_, _, [], _) ->
    [];
dump_tweet_into_bucket_selected(Tweet, TweetId, MentionCaptured, Pid) ->
    [CurrentMention | Remainder] = MentionCaptured,
    {Start, Length} = lists:nth(1, CurrentMention),
    MentionString = string:slice(Tweet, Start, Length),
    StringWithoutMention = string:prefix(MentionString, "@"),
    FinalString =  string:concat("mention_", StringWithoutMention),
    FinalStringUsers = string:concat(FinalString, "_users"),
    ShowQuery = string:concat(string:concat("SHOW TABLES LIKE '", FinalString), "';"),
    {ok, _, Res0} = mysql:query(Pid, ShowQuery),
    if length(Res0) == 0 ->
        FinalStringQuery = string:concat(string:concat("CREATE TABLE ", FinalString), " (tweetID INT);"),
        FinalStringUsersQuery = string:concat(string:concat("CREATE TABLE ", FinalStringUsers), " (username varchar(255) UNIQUE);"),
        ok = mysql:query(Pid, FinalStringQuery),
        ok = mysql:query(Pid, FinalStringUsersQuery);
    true ->
        ok
    end,
    InsertQuery = string:concat(string:concat("INSERT INTO ", FinalString), " VALUES (?);"),
    ok = mysql:query(Pid, InsertQuery, [TweetId]),
    SelectQuery = string:concat(string:concat("SELECT * from ", FinalStringUsers), ";"),
    case mysql:query(Pid, SelectQuery) of
        {ok, _, Res2} ->
            ok;
        {error, _} ->
            Res2 = []
    end,
    Res2 ++ dump_tweet_into_bucket_selected(Tweet, TweetId, Remainder, Pid).

send_tweets(_, [], _, _, _) ->
    ok;
send_tweets(Tweet, FinalUsers, LoggedIn, Username, TweetId) ->
    [User | Remainder] = FinalUsers,
    UserString = binary_to_list(lists:nth(1, User)),
    case dict:find(UserString, LoggedIn) of
        {ok, ClientPid} ->
            ClientPid ! {new_tweet, Tweet, Username, TweetId}; % Username is the user who made the tweet
        error ->
            ok
    end,
    send_tweets(Tweet, Remainder, LoggedIn, Username, TweetId).

subscribe_to(Username, Name) ->
    {ok, Pid} = mysql:start_link([{host, "localhost"}, {user, "root"}, {database, "twitterDB"}]),
    case string:prefix(Name, "hash_") of
        nomatch ->
            MatchHash = false;
        _ ->
            ShowQuery = string:concat(string:concat("SHOW TABLES LIKE '", Name), "';"),
            {ok, _, Res0} = mysql:query(Pid, ShowQuery),
            if length(Res0) == 0 ->
                NameQuery = string:concat(string:concat("CREATE TABLE ", Name), " (tweetID INT);"),
                NameUsersQuery = string:concat(string:concat("CREATE TABLE ", string:concat(Name, "_users")), " (username varchar(255) UNIQUE);"),
                ok = mysql:query(Pid, NameQuery),
                ok = mysql:query(Pid, NameUsersQuery);
            true ->
                ok
            end,
            InsertQuery = string:concat(string:concat("INSERT IGNORE INTO ", string:concat(Name, "_users")), " VALUES(?)"),
            ok = mysql:query(Pid, InsertQuery, [Username]),
            MatchHash = true
    end,
    case string:prefix(Name, "mention_") of
        nomatch ->
            MatchMention = false;
        _ ->
            ShowQuery1 = string:concat(string:concat("SHOW TABLES LIKE '", Name), "';"),
            {ok, _, Res1} = mysql:query(Pid, ShowQuery1),
            if length(Res1) == 0 ->
                NameQuery1 = string:concat(string:concat("CREATE TABLE ", Name), " (tweetID INT);"),
                NameUsersQuery1 = string:concat(string:concat("CREATE TABLE ", string:concat(Name, "_users")), " (username varchar(255) UNIQUE);"),
                ok = mysql:query(Pid, NameQuery1),
                ok = mysql:query(Pid, NameUsersQuery1);
            true ->
                ok
            end,
            InsertQuery1 = string:concat(string:concat("INSERT IGNORE INTO ", string:concat(Name, "_users")), " VALUES(?)"),
            ok = mysql:query(Pid, InsertQuery1, [Username]),
            MatchMention = true
    end,
    if (MatchMention == false) and (MatchHash == false) ->
        ShowQuery2 = string:concat(string:concat("SHOW TABLES LIKE '", string:concat(Name, "_subscribers")), "';"),
        {ok, _, Res2} = mysql:query(Pid, ShowQuery2),
        if length(Res2) == 0 ->
            ok;
        true ->
            InsertQuery2 = string:concat(string:concat("INSERT IGNORE INTO ",string:concat(Name, "_subscribers")), " VALUES(?)"),
            ok = mysql:query(Pid, InsertQuery2, [Username])
        end;
    true ->
        ok
    end,
    mysql:stop(Pid),
    exit(thread_complete).

query_tweets(Username, Name) ->
    {ok, Pid} = mysql:start_link([{host, "localhost"}, {user, "root"}, {database, "twitterDB"}]),
    case string:prefix(Name, "hash_") of
        nomatch ->
            MatchHash = false;
        _ ->
            ShowQuery = string:concat(string:concat("SHOW TABLES LIKE '", Name), "';"),
            {ok, _, Res0} = mysql:query(Pid, ShowQuery),
            if length(Res0) == 0 ->
                server ! {server_query, error, error, error, error};
            true ->
                SelectQuery = string:concat(string:concat("SELECT * FROM ", Name), " ORDER BY tweetID DESC LIMIT 1;"),
                {ok, _, SelectRes} = mysql:query(Pid, SelectQuery),
                if SelectRes == [] ->
                    server ! {server_query, error, error, error, error};
                true ->
                    TweetId = lists:nth(1, lists:nth(1, SelectRes)),
                    {ok, _, SelectRes1} = mysql:query(Pid, "SELECT username, tweet FROM tblUserTweets WHERE tweetID = ?",[TweetId]),
                    {TweeterName, Tweet} = lists:nth(1, lists:nth(1, SelectRes1)),
                    TweeterNameString = binary_to_list(TweeterName),
                    TweetString = binary_to_list(Tweet),
                    server ! {server_query, Username, TweetString, TweetId, TweeterNameString}
                end
            end,
            MatchHash = true
    end,
    case string:prefix(Name, "mention_") of
        nomatch ->
            MatchMention = false;
        _ ->
            ShowQuery1 = string:concat(string:concat("SHOW TABLES LIKE '", Name), "';"),
            {ok, _, Res1} = mysql:query(Pid, ShowQuery1),
            if length(Res1) == 0 ->
                server ! {server_query, error, error, error, error};
            true ->
                SelectQuery1 = string:concat(string:concat("SELECT * FROM ", Name), " ORDER BY tweetID DESC LIMIT 1;"),
                {ok, _, SelectRes2} = mysql:query(Pid, SelectQuery1),
                if SelectRes2 == [] ->
                    server ! {server_query, error, error, error, error};
                true ->
                    TweetId1 = lists:nth(1, lists:nth(1, SelectRes2)),
                    {ok, _, SelectRes3} = mysql:query(Pid, "SELECT username, tweet FROM tblUserTweets WHERE tweetID = ?",[TweetId1]),
                    {TweeterName1, Tweet1} = lists:nth(1, lists:nth(1, SelectRes3)),
                    TweeterNameString1 = binary_to_list(TweeterName1),
                    TweetString1 = binary_to_list(Tweet1),
                    server ! {server_query, Username, TweetString1, TweetId1, TweeterNameString1}
                end
            end,
            MatchMention = true
    end,
    if (MatchMention == false) and (MatchHash == false) ->
        SelectQuery2 = "SELECT tweet, tweetID FROM tblUserTweets WHERE username = (?) ORDER BY tweetID DESC LIMIT 1",
        {ok, _, SelectRes4} = mysql:query(Pid, SelectQuery2, [Name]),
        if SelectRes4 == [] ->
            server ! {server_query, error, error, error, error};
        true ->
            {Tweet2, TweetId2} = lists:nth(1, lists:nth(1, SelectRes4)),
            TweetString2 = binary_to_list(Tweet2),
            server ! {server_query, Username, TweetString2, TweetId2, Name}
        end;
    true ->
        ok
    end,
    mysql:stop(Pid),
    exit(thread_complete).

retweet(Username, TweetId) ->
    {ok, Pid} = mysql:start_link([{host, "localhost"}, {user, "root"}, {database, "twitterDB"}]),
    SelectQuery = "SELECT username, tweet FROM tblUserTweets WHERE tweetID = (?)",
    {ok, _, SelectRes} = mysql:query(Pid, SelectQuery, [TweetId]),
    mysql:stop(Pid),
    if SelectRes == [] ->
        {server_tweet, error, Username, error, error, error};
    true ->
        [Tweeter_raw, Tweet_raw] = lists:nth(1, SelectRes),
        Tweet = binary_to_list(Tweet_raw),
        Tweeter = binary_to_list(Tweeter_raw),
        NewTweet = string:concat(string:concat(Tweeter, " said : \""), string:concat(Tweet, "\"")),
        client_tweet(Username, NewTweet)
    end.

    -spec start_link() -> {ok, pid()}.
    start_link() ->
        gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).
    
    -spec stop() -> stopped.
    stop() ->
        gen_server:call(?MODULE, stop).

        -spec start(_, _) -> {ok, pid()}.
        starter(_, _) ->
            cowboy_sup:start_link().
        
        -spec stop(_) -> ok.
        stop(_) ->
            ok.
