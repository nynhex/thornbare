App.game = App.cable.subscriptions.create "GameChannel",

  connected: ->
    # Called when the subscription is ready for use on the server

  disconnected: ->
    # Called when the subscription has been terminated by the server

  received: (data) ->
    $('document.body').html(data.game)
    if data.move_result?
      doMove(data.move_result)
    if data.card?
      showCard(data.card)

  thisPlayerIsCurrentPlayer: () ->
    thisPlayer = $('#this-player').data("name")
    currentPlayer = $('#current-player').data("name")
    if thisPlayer == currentPlayer
      alert(thisPlayer + " is " + currentPlayer)
      return true
    else
      alert(thisPlayer + " is not " + currentPlayer)
      return false

  enableRollToMove = () ->
    # if thisPlayerIsCurrentPlayer == true
      $('#roll-to-move-button').removeClass('disabled')
      $('#roll-to-move-button').click ->
        $.post 'roll_to_move', {}, (data, status) ->
          return
        return

  disableRollToMove = () ->
    $('#roll-to-move-button').off('click')
    $('#roll-to-move-button').addClass('disabled')

  enableDrawACard = () ->
    # if thisPlayerIsCurrentPlayer == true
      $('#draw-a-card-button').removeClass('disabled')
      $('#draw-a-card-button').click ->
        $.post 'draw_card', {}, (data, status) ->
          return
        return

  disableDrawACard = () ->
    $('#draw-a-card-button').off('click')
    $('#draw-a-card-button').addClass('disabled')

  doMove = (result) ->
    $('#dice-result').addClass('appear')
    $('#dice-result').text("You rolled a " + result)
    current_position = parseInt($('#current-player').data("position"))
    new_space = $('#space-' + ((current_position + result) % 32))
    new_position = new_space.offset()
    $('#current-player').animate {
      left: new_position.left + Math.floor(Math.random() * 50),
      top: new_position.top + Math.floor(Math.random() * 50)
    }, 1000, ->
      $('#dice-result').removeClass('appear')
      $('#building').css("background-image", "url(/assets/buildings/building_" + (current_position + result) + ".jpg)")
      $('#card-button').removeClass('disabled')
      disableRollToMove()
      enableDrawACard()
      return

  showCard = (card) ->
    $('#drawn-card').addClass('appear')
    $('#drawn-card').css("background-image", "url(/assets/cards/" + card + ".png)")
    disableDrawACard()
    setTimeout (->
      $('#drawn-card').removeClass 'appear'
      return
    ), 4000

  enableRollToMove()
  disableDrawACard()
