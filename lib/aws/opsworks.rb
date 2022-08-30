require_relative 'ops'

class Ops::Opsworks < Ops::Base
  attr_accessor :stack, :stack_filter, :command, :instance_id

  def initialize
    CLI::UI::Spinner.spin('Loading stacks') { stacks }

    CLI::UI::Prompt.ask('Choose stack') do |handler|
      stacks.each do |stack|
        handler.option(stack.name)  { |selection| self.stack = stack }
      end
    end
  end

  def commands
    {
      deploy: :deploy,
      start_instance: :start_instance,
      set_app_source: :set_app_source,
    }
  end

  def run
    render_instances
    choose_command
  end

  def list
    render_instances(wait: false)
    choose_command
  end

  def decorate_status(status)
    status + " "*(12-status.size) rescue status
  end

  def decorate(string, width)
    string + " "*(width-string.size) rescue string
  end

  def deploy
    app = client.describe_apps(stack_id: stack.stack_id).apps.first

    layer_ids = []

    CLI::UI::Prompt.ask('Choose layer') do |handler|
      handler.option('all') { |selection| layer_ids = layers.map(&:layer_id) }
      layers.each do |layer|
        handler.option(layer.name)  { |selection| layer_ids = [layer.layer_id] }
      end
    end

    deployment =
      client.create_deployment(
        stack_id: app.stack_id,
        app_id: app.app_id,
        layer_ids: layer_ids,
        command: { name: 'deploy' }
      )

    url = "https://us-east-1.console.aws.amazon.com/opsworks/home?region=eu-west-1\#"
    url << "/stack/#{stack.stack_id}/deployments/#{deployment.deployment_id}"

    puts "Got deployment: #{url}"
    puts "Waiting for deployment to complete"

    # client.wait_until(:deployment_successful, deployment_ids: [deployment.deployment_id])

    render_instances(wait: true)
  end

  def describe_deployment(deployment_id)
    list = client.describe_deployments(
      deployment_ids: [deployment_id]
    )
  end

  def start_instance
    CLI::UI::Prompt.ask('Choose instance') do |handler|
      instances.each do |instance|
        next if instance.status == 'online'

        handler.option(instance.hostname)  do |o|
          client.start_instance(instance_id: instance.instance_id)
        end
      end
    end

    render_instances
  end

  def stop_instance
    CLI::UI::Prompt.ask('Choose instance') do |handler|
      instances.each do |instance|
        next unless %w(online start_failed).include?(instance.status)

        handler.option(instance.hostname)  do |o|
          client.stop_instance(instance_id: instance.instance_id)
        end
      end
    end

    render_instances
  end

  def stacks
    @_stacks ||= client.describe_stacks.stacks.
      map{ |i| [OpenStruct.new(name: i.name, stack_id: i.stack_id)] }.
      flatten
  end

  def client
    @_client ||= Aws::OpsWorks::Client.new(
      region: 'eu-west-1',
      credentials: role_credentials
    )
  end

  def app_source
    @_app_source ||= client.describe_apps(stack_id: stack.stack_id).apps.first.app_source
  end

  def set_app_source
    app = client.describe_apps(stack_id: stack.stack_id).apps.first
    app_source = app.app_source

    key, value = nil, nil

    CLI::UI::Prompt.ask('Choose environment variable') do |handler|
      app_source.each_pair do |k, v|
        handler.option("#{k}: #{v}")  { |o| key = k }
      end
    end

    value = CLI::UI.ask("New value for #{key}, default:#{app_source[key]}")
    puts "value: #{value}"

    client.update_app(app_id: app.app_id, app_source: { key.to_sym => value } )

    app = client.describe_apps(stack_id: stack.stack_id).apps.first
    puts app_source.inspect
  end

  def instances
    @_instances ||= client.describe_instances(stack_id: stack.stack_id).instances
  end

  def layers
    @_layers ||= client.describe_layers(stack_id: stack.stack_id).layers
  end

  def logs
    @_logs = Aws::CloudWatchLogs::Client.new(
      region: 'eu-west-1',
      credentials: role_credentials,
    )
    log_groups = [
      "TermigratorAU/job_processing/srv/www/termigrator/shared/log/production.log",
      "TermigratorAU/job_processing/srv/www/termigrator/shared/log/shoryuken.log",
      "TermigratorProdEU/job_processing/srv/www/termigrator/shared/log/production.log",
      "TermigratorProdEU/job_processing/srv/www/termigrator/shared/log/shoryuken.log"
    ]

    CLI::UI::Prompt.ask('Choose group') do |handler|
      log_groups.each do |group|
        handler.option(group)  { |o| log_streams(group) }
      end
    end
  end

  def render_instances(wait: true)
    CLI::UI::Spinner.spin('Loading instances') { instances }

    spin_group = CLI::UI::SpinGroup.new(auto_debrief: false)

    instances.map do |i|

      string = [
        decorate_status(i.status),
        i.instance_id,
        decorate(i.hostname, instances.map{ |i| i.hostname.size }.max),
        decorate(i.public_ip, instances.map{ |i| i.public_ip.size }.max),
        app_source.revision
        #"ssh:// core_team_engineer-antondiachuk@#{i.public_ip}"
      ].join(' | ')

      spin_group.add(string) do |spinner|
        if i.status == 'stopping'
          client.wait_until(:instance_stopped, instance_ids: [i.instance_id]) if wait
        elsif i.status != 'online'
          begin
            client.wait_until(:instance_online, instance_ids: [i.instance_id]) if wait
          rescue => e
            spinner.instance_variable_set(:@success, false)
            spinner.instance_variable_set(:@done, true)
          end
        end
      end
    end

    spin_group.wait
  end
end
