# frozen_string_literal: true

module Lrama
  class Diagnostics
    def initialize(grammar, states, logger)
      @grammar = grammar
      @states = states
      @logger = logger
    end

    def run(diagnostic)
      if diagnostic
        diagnose_conflict
        diagnose_parameterized_redefined
      end
    end

    private

    def diagnose_conflict
      if @states.sr_conflicts_count != 0
        @logger.warn("shift/reduce conflicts: #{@states.sr_conflicts_count} found")
      end

      if  @states.rr_conflicts_count != 0
        @logger.warn("reduce/reduce conflicts: #{@states.rr_conflicts_count} found")
      end
    end

    def diagnose_parameterized_redefined
      @grammar.parameterized_resolver.redefined_rules.each do |rule|
        @logger.warn("parameterized rule redefined: #{rule}")
      end
    end
  end
end
