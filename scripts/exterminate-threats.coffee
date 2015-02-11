# Description:
#   Exterminate threats
#
# Dependencies:
#   None
#
# Commands:
#   hubot fun fact me
#
# Author:
#   jacobwgillespie


module.exports = (robot) ->
  robot.respond /(exterminate|eliminate) (the|all) threats/i, (msg) ->
    msg.send "Threats eliminated!"

  robot.respond /(exterminate|eliminate) threat/i, (msg) ->
    msg.send "Threat eliminated!"
