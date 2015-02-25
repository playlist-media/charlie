# Description:
#   Deploys code to staging / production
#
# Dependencies:
#   None
#
# Commands:
#   hubot <stack> [<environment>] status - show status for the specified stack (and optional environment)
#   hubot <stack> [<environment>] maintenance (on|off) - set maintenance mode status for the specified stack (and optional environment)
#   hubot deploy <stack> [<branch>] [to <environment>] - deploy stack with an optional branch to an optional environment (default: master, production)
#
# Author:
#   jacobwgillespie

greetings = ["Coming right up", "Kicking it now", "On it sir", "Let's do it", "You got it"]

STATUS = {
 0: 'pending analysis',
 1: 'deployed successfully',
 2: 'deployment failed',
 3: 'analyzing',
 4: 'analyzed',
 5: 'queued for deployment',
 6: 'deploying',
 7: 'unable to analyze',
}

HEALTH = {
  0: 'at unknown status',
  1: 'building',
  2: 'impaired',
  3: 'healthy',
  4: 'failed'
}

api_key = process.env.CLOUD66_API_KEY

module.exports = (robot) ->
  robot.pendingDeploys = {}

  robot.router.post '/hubot/deploy', (req, res) ->
    data = req.body
    stack_id = data.uid
    started_at = new Date(data.deploy_context.started_at)

    res.end "true"


    return unless robot.pendingDeploys[stack_id] && robot.pendingDeploys[stack_id].length > 0

    last_deploy = robot.pendingDeploys[stack_id].shift()

    if last_deploy.created_at <= started_at
      if data.event_type == 'stack.redeploy.ok'
        robot.messageRoom last_deploy.room, "Success! #{last_deploy.stack} (#{last_deploy.branch}) deployed to #{last_deploy.environment}!"
      else if data.event_type == 'stack.redeploy.fail'
        robot.messageRoom last_deploy.room, "Failure! Unable to deploy #{last_deploy.stack} (#{last_deploy.branch}) to #{last_deploy.environment}!"
    else
      robot.pendingDeploys[stack_id].unshift(last_deploy)

  robot.respond /([^\s]+)( ([^\s]+))? status$/, (msg) ->
    stack = msg.match[1]
    environment = msg.match[3] || 'production'

    env_var = "CLOUD66_S_#{stack.toUpperCase()}_#{environment.toUpperCase()}"
    stack_id = process.env[env_var]

    unless stack_id
      return msg.send("Oops, it seems I don't know how to find #{stack} on #{environment} (looking for env var #{env_var})")

    robot.http("https://app.cloud66.com/api/3/stacks/#{stack_id}")
      .header('Authorization', "Bearer #{api_key}")
      .get() (err, res, body) ->
        if err
          msg.send "Whoops! Something is not right: (#{err})"
          return
        data = JSON.parse(body).response
        if data.uid
          maintenance = if data.maintenance_mode then '  Maintenance mode is enabled.' else ''
          msg.send "Stack #{stack} is currently #{STATUS[data.status]} and is #{HEALTH[data.health]}.#{maintenance}"
        else
          msg.send "Erm! This doesn't look right: #{data}"

  robot.respond /([^\s]+)( ([^\s]+))? restart$/, (msg) ->
    stack = msg.match[1]
    environment = msg.match[3] || 'production'

    env_var = "CLOUD66_S_#{stack.toUpperCase()}_#{environment.toUpperCase()}"
    stack_id = process.env[env_var]

    unless stack_id
      return msg.send("Oops, it seems I don't know how to find #{stack} on #{environment} (looking for env var #{env_var})")

    data = JSON.stringify(command: 'restart')
    robot.http("https://app.cloud66.com/api/3/stacks/#{stack_id}/actions")
      .header('Authorization', "Bearer #{api_key}")
      .post(post) (err, res, body) ->
        if err
          msg.send "Whoops! Something is not right: (#{err})"
          return
        data = JSON.parse(body).response
        if data.action
          msg.send greetings[Math.floor(Math.random() * greetings.length)]
        else
          msg.send "Erm! This doesn't look right: #{data}"

  robot.respond /([^\s]+)( ([^\s]+))? maintenance (on|off)$/, (msg) ->
    stack = msg.match[1]
    environment = msg.match[3] || 'production'
    enable = msg.match[4] == 'on'

    env_var = "CLOUD66_S_#{stack.toUpperCase()}_#{environment.toUpperCase()}"
    stack_id = process.env[env_var]

    unless stack_id
      return msg.send("Oops, it seems I don't know how to find #{stack} on #{environment} (looking for env var #{env_var})")

    data = { command: 'maintenance_mode' }
    data.value = (if enable then "1" else "0")
    data = JSON.stringify(data)
    robot.http("https://app.cloud66.com/api/3/stacks/#{stack_id}/actions")
      .header('Authorization', "Bearer #{api_key}")
      .header('Content-Type', 'application/json; charset=utf-8')
      .post(data) (err, res, body) ->
        if err
          msg.send "Whoops! Something is not right: (#{err})"
          return
        data = JSON.parse(body).response
        if data.action
          msg.send greetings[Math.floor(Math.random() * greetings.length)]
        else
          msg.send "Erm! This doesn't look right: #{data}"

  robot.respond /deploy ([^\s]*)( ([^\s]*))?( to ([^\s]*))?/i, (msg) ->
    stack = msg.match[1]
    branch = msg.match[3] || 'master'
    environment = msg.match[5] || 'production'

    env_var = "CLOUD66_S_#{stack.toUpperCase()}_#{environment.toUpperCase()}"
    stack_id = process.env[env_var]

    unless stack_id
      return msg.send("Oops, it seems I don't know how to deploy #{stack} on #{environment} (looking for env var #{env_var})")

    msg.send "Are you sure you want to deploy #{stack} (#{branch}) to #{environment}?  (yes/no)"
    msg.waitResponse (msg) ->
      text = msg.message.text
      matches = text.match(if robot.enableSlash then new RegExp("^(?:\/|#{robot.name}:?)\\s*(.*?)\\s*$", 'i') else new RegExp("^#{robot.name}:?\\s*(.*?)\\s*$", 'i'))
      if text == 'yes' || (matches && matches[1] == 'yes')
        msg.send greetings[Math.floor(Math.random() * greetings.length)]

        created_at = new Date(Date.now())
        room = msg.message.room
        data = JSON.stringify(git_ref: branch)

        robot.http("https://app.cloud66.com/api/3/stacks/#{stack_id}/deployments")
          .header('Authorization', "Bearer #{api_key}")
          .post(data) (err, res, body) ->
            if err
              msg.send "Whoops! Something is not right: (#{err})"
              return
            data = JSON.parse(body).response
            if data.ok
              robot.pendingDeploys[stack_id] ?= []
              robot.pendingDeploys[stack_id].push(
                room: room,
                created_at: created_at,
                stack: stack,
                branch: branch,
                environment: environment
              )
            else
              msg.send "Erm! This doesn't look right: #{data.message}"

      else
        msg.send "Canceling..."

