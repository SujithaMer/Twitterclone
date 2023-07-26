-module(client).

-compile(nowarn_export_all).
-compile(export_all).

start(Server) ->
    net_adm:ping(Server),
    UserInput = string:chomp(io:get_line("1. Login\n2. Register\n")),
    if UserInput == "1" ->
        io:fwrite("\n\nClient started\n\n "),
        Num = io:get_line("Enter options: \n1.Create user \n2.Login\n"),
        io:fwrite("\nSelection option ~p Enter user info:\n ",[Num]),
        io:fwrite("Enter your login credentials:\n"),
        Name = io:get_line("User Email:"),
        io:fwrite("\nUser ~p logged in!",[Name]),
        Op = io:get_line("Enter options: \n1.Tweet \n2.Re-tweet \n3.Query  \n4.Subscribe\n"),
        io:fwrite("\nSelected option ~p \nEnter User or Hashtag to subscribe:\n ",[Op] ),
        Twe = io:get_line("User or Hastag:"),
        io:fwrite("\nSubscribed to ~p successfully!\n ",[Twe]),
        login(Server);
    true ->
        io:fwrite("Enter your regitration credentials:\n"),
        register(Server)  
    end,
    start_listening(Server).

start_listening() ->
    receive
        {tweet_response, error} ->
            io:fwrite("ERROR\n");
        {tweet_response, ok} ->
            io:fwrite("Tweeted successfully\n");
        {query_response, Tweet, TweetId, Tweeter} ->
            io:fwrite("Query Response \nTweet\t~p \nTweeter \t~p \nTweetID\t~p\n", [Tweet, Tweeter, TweetId]);
        {new_tweet, Tweet, Tweeter, TweetId} ->
            io:fwrite("New Tweet \nTweet\t~p \nTweeter \t~p \nTweetID\t~p\n", [Tweet, Tweeter, TweetId])
    end,
    start_listening().

start_listening(Server) ->
    receive
        {login_response, Username, ok} ->
            io:fwrite("Login Successful:\n"),
            spawn_link(client, start_tweeting, [Server, Username]),
            start_listening();
        {register_response, Username, ok} ->
            io:fwrite("Registration Successful:\n"),
            spawn_link(client, start_tweeting, [Server, Username]),
            start_listening();
        {login_response, error} ->
            io:fwrite("Error logging in:\n"),
            start(Server);
        {register_response, error} ->
            io:fwrite("Error registering in:\n"),
            start(Server)
    end.

start_tweeting(Server, Username) ->
    Operation = string:chomp(io:get_line("1.Write a tweet \n2.Search \n3.Subscribe \n4.Retweet\n:")),
    case Operation of 
        "1" -> tweet(Server, Username);
        "2" -> query(Server, Username);
        "3" -> subscribe(Server, Username);
        "4" -> retweet(Server, Username);
        _ -> ok
    end,
    start_tweeting(Server, Username).

register(Server) ->
    Username = string:chomp(io:get_line("Enter your Username:\n")),
    Password = string:chomp(io:get_line("Enter your Password:\n")),
    {server, Server} ! {client_register, self(), Username, Password}.
    
login(Server)->
    Username = string:chomp(io:get_line("Enter your Username:\n")),
    Password = string:chomp(io:get_line("Enter your Password:\n")),
    {server, Server}  ! {client_login, self(), Username, Password}.

tweet(Server, Username) ->
    Tweet = string:chomp(io:get_line("Enter your tweet:\n")),
    {server, Server}  ! {client_tweet, Username, Tweet}.

subscribe(Server, Username) ->
    New_subscription_raw = string:chomp(io:get_line("Enter your subscription:\n")),
    New_subscription = process_string(New_subscription_raw),
    {server, Server}  ! {client_subscribe_to, Username, New_subscription}.

query(Server, Username)->
    Query_raw = string:chomp(io:get_line("Enter your query:\n")),
    Query = process_string(Query_raw),
    {server, Server}  ! {client_query, Username, Query}.

process_string(String) ->
    case string:prefix(String, "#") of
        nomatch ->
            case string:prefix(String, "@") of
                nomatch ->
                    ReturnString = String;
                StringWithoutMention ->
                    ReturnString =  string:concat("mention_", StringWithoutMention)
            end;
        StringWithoutHash ->
            ReturnString =  string:concat("hash_", StringWithoutHash)
    end,
    ReturnString.

retweet(Server, Username)->
    {ok, TweetId} = io:read("Enter the tweet ID you'd like to retweet.\n"),
    {server, Server} ! {client_retweet, Username, TweetId}.
