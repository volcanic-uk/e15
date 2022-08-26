require_relative 'ops'

class Ops::Root < Ops::Base
  def run
    CLI::UI::Prompt.ask('Choose an option:') do |handler|
      handler.option('Opsworks') { |o| Ops::Opsworks.new.run}
      handler.option('SQS') { |o| Ops::SQS.new.run}
    end
  end
end
