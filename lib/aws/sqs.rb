require_relative 'ops'
require_relative 'opsworks'

class Ops::SQS < Ops::Base
  def commands
    {
      list_queues: :list_queues,
      purge_queue: :purge_queue
    }
  end

  def client
    @_client ||= Aws::SQS::Client.new(
      region: 'eu-west-1'
    )
  end

  def run
    choose_command
  end

  def queues
    queue_urls.queue_urls.to_a.map do |url|
      attrs_to_struct(get_queue_attributes(url), url)
    end
  end

  def attrs_to_struct(attrs, url)
    name = attrs["QueueArn"].split(':').last
    messages = attrs["ApproximateNumberOfMessages"].to_i
    in_flight = attrs["ApproximateNumberOfMessagesNotVisible"].to_i

    OpenStruct.new(
      name: name,
      arn: attrs["QueueArn"],
      url: url,
      messages: messages,
      in_flight: in_flight,
      decorate: -> {
        [
          name + " " * (41 - name.length),
          messages,
          in_flight
        ].join(' | ')
      }
    )
  rescue
    raise attrs.inspect
  end

  def queue_urls
    @_queue_urls = client.list_queues(queue_name_prefix: 'migrate_production')
  end

  def list_queues
    puts ["Queue name:                                  ", "\t\t", "Total messages:", "\t", "Messages in flight:"].join
    spin_group = CLI::UI::SpinGroup.new

    queues.each do |queue|
      spin_group.add(queue.decorate.()) do |spinner|
        update_queue(queue, spinner)
      end
    end

    spin_group.wait
    choose_command
  end

  def get_queue_attributes(url)
    response = client.get_queue_attributes({
      queue_url: url,
      attribute_names: ["QueueArn", "ApproximateNumberOfMessages", "ApproximateNumberOfMessagesNotVisible"]
    }).attributes
  end

  def update_queue(queue, spinner)
    queue.in_flight = get_queue_attributes(queue.url)['ApproximateNumberOfMessagesNotVisible'].to_i
    spinner.update_title(queue.decorate.())
  end

  def purge_queue
    CLI::UI::Spinner.spin('Loading queues') { queues }

    CLI::UI::Prompt.ask('Choose queue') do |handler|
      queues.each do |queue|
        handler.option(queue.decorate.())  { |o| client.purge_queue(queue_url: queue.url) }
      end
    end
  end

  def create_queue
    CLI::UI::Prompt.ask('Create queue') do |handler|
      handler.option('Create')  { |o| client.create_queue(queue_name: 'migrate_production') }
    end
  end
end
