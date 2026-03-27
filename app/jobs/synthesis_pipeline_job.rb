class SynthesisPipelineJob < ApplicationJob
  queue_as :synthesis

  def perform(*args)
    # Do something later
  end
end
