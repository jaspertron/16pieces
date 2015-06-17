var buildGame = function(gameId, password, fen, color){
    var submitMove = function(source, target, piece, preMoveFen, pawnPromotion){
      var moveUrl = "/move/" + gameId + "/" + color[0] + "/" + password + "/" + source + "-" + target + pawnPromotion;
      $.post(moveUrl)
        .done(function(moveResponse){
          game.load(moveResponse.fen);
          board.position(game.fen());
          updateStatus();})
        .fail(function(xhr){
          console.log('Illegal move');
          game.load(preMoveFen);
          board.position(game.fen());})
        .complete(function(){
          pollServer();});
    };
    var onDrop = function(source, target, piece) {
      var preMoveFen = game.fen();

      // snapback illegal moves
      var dummyGame = new Chess(game.fen());
      var illegal = dummyGame.move({
        from: source,
        to: target,
        promotion: 'q' //dummy promotion just to see if move is legal
      }) === null;
      if (illegal) return 'snapback';

      //pawn promotion
      if (/1|8/.test(target) && /P/.test(piece)) {

        // modal is closed
        var dismiss = function(){
          removeEventHandlers();
          board.position(preMoveFen);
        };

        // a piece is chosen
        var promote = function(promotion){
          removeEventHandlers();
          $('#promotion-modal').modal('hide');
          game.move({
            from: source,
            to: target,
            promotion: promotion[1].toLowerCase()
          });
          board.position(game.fen());
          submitMove(source, target, piece, preMoveFen, promotion);
        };

        var promoteQueen = function(){promote('(Q)');};
        var promoteKnight = function(){promote('(N)');};
        var promoteRook = function(){promote('(R)');};
        var promoteBishop = function(){promote('(B)');};

        var addEventHandlers = function(){
          $('#promotion-modal').on('hide.bs.modal', dismiss);
          $('#promotion-queen').on('click', promoteQueen);
          $('#promotion-knight').on('click', promoteKnight);
          $('#promotion-rook').on('click', promoteRook);
          $('#promotion-bishop').on('click', promoteBishop);
        };

        var removeEventHandlers = function(){
          $('#promotion-modal').off('hide.bs.modal', dismiss);
          $('#promotion-queen').off('click', promoteQueen);
          $('#promotion-knight').off('click', promoteKnight);
          $('#promotion-rook').off('click', promoteRook);
          $('#promotion-bishop').off('click', promoteBishop);
        };

        addEventHandlers();

        $('#promotion-modal').modal();

      // regular move (not pawn promotion)
      } else {
        game.move({
          from: source,
          to: target
        });
        submitMove(source, target, piece, preMoveFen, "");
      }
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
    var board;
    var game = new Chess(fen);
    var pollServer = function(){
      console.log('polling server');
      $.get("/game/" + gameId + "/" + color[0] + "/" + password + "?longpoll")
      .done(function(data){
        console.log(data);

        // highlight opponent's latest move
        // note: the server doesn't keep track of move history, so
        // the latest move will be lost if the page is refreshed
        clearHighlights();
        highlightSquares(diff(game.fen(), data.fen));

        game.load(data.fen);
        board.position(game.fen());
        if(data.joincode === null) $('#joincode-message').slideUp();})
      .complete(function(){
        updateStatus();
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
    var updateStatus = function(){
        if (game.in_checkmate()) setStatus(opponentsTurn()? "Checkmate! You won!" : "Checkmate! You lost!");
        else if (game.in_draw() || game.in_stalemate() || game.in_threefold_repetition()) setStatus("Alright, we'll call it a draw.");
        else setStatus(opponentsTurn()? "Waiting for opponent" : "It's your turn");
    };
    var drawBoard = function(position){
      // preserve highlights
      var highlighted = $('.highlight').map(function(){ return $(this).data('square'); });

      // we don't want the board to be larger than the window
      var maxSize = Math.min($(window).width(), $(window).height());

      // we want sizeWithoutBorders to be divisible by 8
      // so that the board is completely filled by the squares
      var sizeWithoutBorders = maxSize - (maxSize % 8);
      var sizeWithBorders = sizeWithoutBorders + 4;

      // we also need sizeWithBorders <= maxSize
      while (sizeWithBorders >= maxSize) sizeWithBorders -= 8;

      $('#chessboard').width(sizeWithBorders);
      cfg.position = position;
      board = new ChessBoard('chessboard', cfg);

      // restore highlights
      highlightSquares($.makeArray(highlighted));
    };
    var highlightSquares = function(squares){
      squares.forEach(function(sq){
        $('.square-'+sq).addClass('highlight');
      });
    };
    var clearHighlights = function(){
      $('.square-55d63').removeClass('highlight');
    };
    // get a list of squares that are different between 2 fen strings
    var diff = function(fen1, fen2) {
      var diffSquares = [];
      var g1 = new Chess(fen1);
      var g2 = new Chess(fen2);
      Chess().SQUARES.forEach(function(sq){
        if(!_.isEqual(g1.get(sq), g2.get(sq))) diffSquares.push(sq);
      });
      return diffSquares;
    };

    $(window).resize(function(){
      drawBoard(game.fen());
    });
    drawBoard(fen);
    updateStatus();
    if (opponentsTurn()) pollServer();
};
