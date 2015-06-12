var buildGame = function(gameId, password, fen, color){
    var submitMove = function(source, target, piece, preMoveFen){
      //todo: prompt user for promotion
      var pawnPromotion = (/1|8/.test(target) && /P/.test(piece)) ? "(Q)" : "";
      var moveUrl = "/move/" + gameId + "/" + color[0] + "/" + password + "/" + source + "-" + target + pawnPromotion;
      $.post(moveUrl)
        .done(function(moveResponse){
          game.load(moveResponse.fen);
          board.position(game.fen());
          updateStatus(false);})
        .fail(function(xhr){
          console.log('Illegal move');
          game.load(preMoveFen);
          board.position(game.fen());})
        .complete(function(){
          pollServer();});
    };
    var onDrop = function(source, target, piece) {
      var preMoveFen = game.fen();
      // see if the move is legal
      var move = game.move({
        from: source,
        to: target,
        promotion: 'q' //todo: prompt user for promotion
      });
      if (move === null) return 'snapback'; // illegal move
      submitMove(source, target, piece, preMoveFen);
    };
    var onDragStart = function(source, piece, position, orientation) {
      // only allow dragging our pieces on our turn
      var ourPiece = new RegExp(color[0]).test(piece);
      var allowDrag = ourPiece && !opponentsTurn();
      return allowDrag;
    };
    var cfg = {
      orientation: color,
      pieceTheme: '/static/img/chesspieces/wikipedia/{piece}.png',
      position: fen,
      draggable: true,
      onDragStart: onDragStart,
      onDrop: onDrop
    };
    var board = new ChessBoard('chessboard', cfg);
    var game = new Chess(fen);
    var pollServer = function(){
      console.log('polling server');
      $.get("/game/" + gameId + "/" + color[0] + "/" + password + "?longpoll")
      .done(function(data){
        console.log(data);
        game.load(data.fen);
        board.position(game.fen());
        if(data.joincode === null) $('#joincode-message').slideUp();})
      .complete(function(){
        updateStatus(!opponentsTurn()); //only notify on our turn
        if (opponentsTurn()) window.setTimeout(pollServer, 1000);
      });
    };
    var opponentsTurn = function(){
      return game.turn() != color[0];
    };
    var setStatus = function(s){
      $('#status').text(s);
      document.title = s;
    };
    var updateStatus = function(shouldNotify){
      var draw = game.in_draw() || game.in_stalemate() || game.in_threefold_repetition();
      var message;
      if (game.in_checkmate()) {
        message = opponentsTurn() ? "Checkmate! You won!" : "Checkmate! You lost!";
      } else if (draw) {
        message = "Alright, we'll call it a draw.";
      } else {
        message = opponentsTurn() ? "Waiting for opponent" : "It's your turn";
      }
      setStatus(message);
      if(shouldNotify) notify(message);
    };
    var notify = function(s){
      if (!("Notification" in window)) {
        console.log("notifications aren't supported in this browser");
        return;
      }
      else if (Notification.permission === "granted") {
        new Notification(s);
      }
      else if (Notification.permission !== "denied") {
        Notification.requestPermission(function (permission) {
          if (permission === "granted") {
            new Notification(s, {icon: "/static/img/chesspieces/wikipedia/wN.png"});
          }
        });
      }
    };

    updateStatus(false); //don't notify since it's the initial page load
    if (opponentsTurn()) pollServer();
};
