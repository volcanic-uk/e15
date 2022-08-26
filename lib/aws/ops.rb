require 'aws-sdk-opsworks'
require 'aws-sdk-sqs'
require 'optparse'
require 'cli/ui'
require 'aws-sdk-cloudwatchlogs'
require 'dotenv'

Dotenv.load('.env')

CLI::UI::StdoutRouter.enable

module Ops
  class Base
    attr_accessor :command

    def initialize
      Aws.config.update({
        credentials: Aws::Credentials.new(
          ENV.fetch('AWS_ACCESS_KEY_ID'),
          ENV.fetch('AWS_SECRET_ACCESS_KEY'),
          ENV.fetch('AWS_SESSION_TOKEN')
        )
     })
    end

    def choose_command
      CLI::UI::Prompt.ask('Choose command') do |handler|
        commands.merge(root: :root).each do |k, v|
          handler.option(k.to_s)  { |o| public_send(v) }
        end
      end
    end

    def role_credentials
      @_role_credentials ||= Aws::AssumeRoleCredentials.new(
        client: Aws::STS::Client.new,
        role_arn: "arn:aws:iam::244803632906:role/OrganizationAccountAccessRole",
        role_session_name: "sandbox"
      )
    end
  end
end
