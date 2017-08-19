class GamesController < ApplicationController

  before_action :scope_game, except: [:index, :create, :new]
  before_action :scope_players, except: [:index, :create, :new]
  before_action :scope_spaces, except: [:index, :create, :new, :show]

  def index
    @games = Game.all
  end

  def create
    @game = Game.create
    @game.update_attributes(round: 0, turn: 0)
    redirect_to @game
  end

  def show
  end

  def start
    @this_player = current_player
    @card = Card.new(name: "encounter", value: 3)
    render :board
  end

  def roll_to_move
    # result = rand(5) + 1
    result = 4
    original_position = @current_player.position
    @current_player.update_attributes!(position: (@current_player.position + result) % 32)
    @current_space = Space.find_by(position: @current_player.position)
    ActionCable.server.broadcast(
      "game_channel",
      {
        players: render_players,
        from_position: original_position,
        to_position: @current_player.position,
        move_result: result
      }
    )
  end

  def show_cards
    ActionCable.server.broadcast(
      "game_channel",
      {
        cards: render_cards
      }
    )
  end

  def draw_card
    if @current_player.position % 4 == 0
#      card = @game.draw_card(@current_player)
      @card = Card.new(name: "encounter", value: 3)
      session[:encounter_value] = @card.value
      if @card.name == "encounter"
        ActionCable.server.broadcast(
          "game_channel",
          {
            encounter: render_encounter,
            card: "#{@card.name}_#{@card.value}",
            value: @card.value,
          }
        )
      else
        ActionCable.server.broadcast(
          "game_channel",
          {
            game: render_game,
            card: "#{@card.name}_#{@card.value}"
          }
        )
      end
    end
  end

  def choose_cards
    ActionCable.server.broadcast(
      "game_channel",
      {
        encounter: render(
          partial: "choose_cards",
          locals: {
            current_player: current_player,
            card: Card.new(name: "encounter", value: session[:encounter_value])
          }
        ),
        step: "choose_cards",
        encounter_value: session[:encounter_value],
      }
    )
  end

  def show_ally_or_distraction
    session[:ally_or_distraction] = { name: params[:name], value: params[:value] }
    ActionCable.server.broadcast(
      "game_channel",
      {
        encounter: render(
          partial: "show_ally_or_distraction",
          locals: {
            card: Card.new(name: session[:ally_or_distraction][:name], value: session[:ally_or_distraction][:value])
          }
        ),
        step: "show_ally_or_distraction",
      }
    )
  end

  def show_rolls
    additional_dice = 0
    dice_reduction = 0
    if session[:ally_or_distraction][:name] == "ally"
      additional_dice = session[:ally_or_distraction][:value].to_i
    elsif session[:ally_or_distraction][:name] == "distraction"
      dice_reduction = session[:ally_or_distraction][:value].to_i
      if session[:encounter_value] - dice_reduction < 1
        dice_reduction += session[:encounter_value] - dice_reduction - 1
      end
    end
    session[:player_result] = Game.roll_dice(1 + additional_dice)
    session[:opponent_result] = Game.roll_dice(session[:encounter_value] - dice_reduction)
    ActionCable.server.broadcast(
      "game_channel",
      {
        encounter: render(
          partial: "rolls",
          locals: {
            player_result: session[:player_result],
            opponent_result: session[:opponent_result]
          }
        ),
        step: "show_rolls"
      }
    )
  end

  def show_outcome
    player_result = session[:player_result]
    opponent_result = session[:opponent_result]

    session[:player_result] = nil
    session[:opponent_result] = nil
    session[:encounter_value] = nil
    session[:ally_or_distraction] = nil

    if player_result == opponent_result
      outcome = "draw"
    elsif player_result > opponent_result
      outcome = "success"
    else
      outcome = "failure"
    end

    resources_lost = Resource.lose(@current_player.resources.map(&:value), session[:encounter_value])
    resources_lost[:remove].each do |value|
      @current_player.resources.find{|r| r.value == value}.destroy
    end
    resources_lost[:change].each do |value|
      @current_player.resources.create(value: value)
    end

    ActionCable.server.broadcast(
      "game_channel",
      {
        encounter: render(
          partial: "outcome",
          locals: {
            outcome: outcome,
            resources_lost: resources_lost[:remove].sum
          }
        ),
        step: "show_outcome"
      }
    )
  end

  def end_encounter
    if !params[:success]
      if params[:card_spent][:name] == "ally"
        current_player.allies.where(value: params[:card_spent][:value]).first.destroy
      end
      outcome = Resource.lose(current_player.resources.map(&:value), params[:resources_lost])
      outcome[:remove].each do |value|
        current_player.resources.find{|resource| resource.value == value}.destroy
      end
      outcome[:change].each do |value|
        current_player.resources.create(value: value)
      end
    end
    if params[:card_spent][:name] == "distraction"
      current_player.distractions.where(value: params[:card_spent][:value]).first.destroy
    end
    @game.next_turn
    if @game.turn == @players.count
      @game.next_round
    end
    @current_player = @players[@game.turn]
    ActionCable.server.broadcast(
      "game_channel",
      {
        game: render_game,
        next_turn: true
      }
    )
  end

  def end_turn
    @game.next_turn
    if @game.turn == @players.count
      @game.next_round
    end
    @current_player = @players.any? && @players[@game.turn]
    ActionCable.server.broadcast(
      "game_channel",
      {
        game: render_game,
        next_turn: true
      }
    )
  end

  private

  def scope_game
    id = params[:id] || params[:game_id]
    @game = Game.find(id)
  end

  def scope_players
    @players = @game.players
    @current_player = @players.any? && @players[@game.turn]
    @connected_player = current_player || Player.new
  end

  def scope_spaces
    @spaces = Space.all
    @current_space = Space.find_by(position: @current_player.position)
  end

  def render_players
    render partial: "players", locals: {
      players: @players,
      current_player: @current_player
    }
  end

  def render_encounter
    render partial: "encounter", locals: { current_player: current_player, card: @card }
  end

  def render_cards
    render partial: "cards", locals: { current_player: current_player }
  end

  def render_game
    render partial: "game", locals: {
      game: @game,
      players: @players,
      spaces: @spaces,
      current_player: @current_player,
      current_space: @current_space,
      connected_player: @connected_player,
      result: rand(5) + 1,
      card: @card
    }
  end

end
