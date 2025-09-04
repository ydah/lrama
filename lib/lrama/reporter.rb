# rbs_inline: enabled
# frozen_string_literal: true

require_relative 'reporter/conflicts'
require_relative 'reporter/grammar'
require_relative 'reporter/precedences'
require_relative 'reporter/profile'
require_relative 'reporter/rules'
require_relative 'reporter/states'
require_relative 'reporter/terms'

module Lrama
  class Reporter
    include Lrama::Tracer::Duration

    # @rbs (mode: Symbol, **bool options) -> void
    def initialize(mode: :text, **options)
      @options = options
      @mode = mode
      @rules = Rules.new(mode: mode, **options)
      @terms = Terms.new(mode: mode, **options)
      @conflicts = Conflicts.new(mode: mode, **options)
      @precedences = Precedences.new(mode: mode, **options)
      @grammar = Grammar.new(mode: mode, **options)
      @states = States.new(mode: mode, **options)
    end

    # @rbs (IO io, Lrama::States states) -> void
    def report(io, states)
      report_html_header(io) if @mode == :html

      report_duration(:report) do
        if @mode == :html
          io.puts <<~HTML
            <div id="summary">
              <h2>Summary</h2>
              <div class="code-block summary-box">
          HTML
          report_duration(:report_conflicts) { @conflicts.report(io, states) }
          report_duration(:report_terms) { @terms.report(io, states) }
          io.puts <<~HTML
              </div>
            </div>
          HTML
          report_duration(:report_rules) { @rules.report(io, states) }
          report_duration(:report_grammar) { @grammar.report(io, states) }
          report_duration(:report_states) { @states.report(io, states, ielr: states.ielr_defined?) }
          report_duration(:report_precedences) { @precedences.report(io, states) }
        else
          report_duration(:report_rules) { @rules.report(io, states) }
          report_duration(:report_terms) { @terms.report(io, states) }
          report_duration(:report_conflicts) { @conflicts.report(io, states) }
          report_duration(:report_grammar) { @grammar.report(io, states) }
          report_duration(:report_precedences) { @precedences.report(io, states) }
          report_duration(:report_states) { @states.report(io, states, ielr: states.ielr_defined?) }
        end
      end

      report_html_footer(io) if @mode == :html
    end

    private

    # @rbs (IO io) -> void
    def report_html_header(io)
      title_suffix = @options[:title] ? " (#{@options[:title]})" : ""
      title = "Parser Generator Output#{title_suffix}"

      io.puts <<~HTML
        <!DOCTYPE html>
        <html lang="ja">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>#{title}</title>
          <style>
            body {
              font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
              line-height: 1;
              color: #333;
              background-color: #fdfdfd;
              margin: 0;
              padding: 20px;
            }
            .container {
              max-width: 1024px;
              margin: 0 auto;
              background-color: #fff;
              padding: 20px 40px;
              border-radius: 8px;
              box-shadow: 0 2px 10px rgba(0, 0, 0, 0.05);
            }
            h1, h2, h3 {
              border-bottom: 2px solid #eee;
              padding-bottom: 10px;
            }
            h1 { color: #1a1a1a; }
            h2 { color: #3a3a3a; }
            h3 {
              color: #4a4a4a;
              font-family: "Menlo", "Monaco", "Courier New", Courier, monospace;
              background-color: #f0f8ff;
              padding: 8px 12px;
              border-radius: 4px;
              border-left: 5px solid #4682b4;
              margin-top: 40px;
            }
            pre, .code-block {
              background-color: #f9f9f9;
              border: 1px solid #ddd;
              border-radius: 4px;
              padding: 15px;
              overflow-x: auto;
              font-family: "Menlo", "Monaco", "Courier New", Courier, monospace;
              font-size: 0.9em;
              line-height: 1.4;
              word-wrap: break-word;
            }
            .state-block { margin-bottom: 30px; }
            a {
              color: #007bff;
              text-decoration: none;
              font-weight: bold;
            }
            a:hover { text-decoration: underline; }
            .conflict { color: #dc3545; font-weight: bold; }
            .conflict-detail {
              background-color: #fbe9e7;
              border: 1px solid #ffab91;
              padding: 10px;
              margin-top: 10px;
              border-radius: 4px;
            }
            .action { color: #28a745; font-weight: bold; }
            .token { color: #17a2b8; }
            .non-terminal { color: #6f42c1; }
            .grammar-list li {
              font-family: "Menlo", "Monaco", "Courier New", Courier, monospace;
              margin-bottom: 5px;
              background-color: #f8f9fa;
              padding: 5px 10px;
              border-radius: 3px;
            }
            .debug-info { color: #6c757d; }
            .debug-header { color: #495057; font-weight: bold; }
            .summary-box { padding: 5px 15px; }
            .summary-box h3 {
              color: #3a3a3a;
              margin-top: 10px;
              margin-bottom: 5px;
              padding-bottom: 0;
              border-bottom: none;
              background-color: transparent;
              border-left: none;
              font-size: 1.1em;
            }
            .summary-box ul {
              margin-top: 0;
              margin-bottom: 10px;
              list-style-position: inside;
              padding-left: 0;
            }
          </style>
        </head>
        <body>
          <div class="container">
            <h1>#{title}</h1>
      HTML
    end

    # @rbs (IO io) -> void
    def report_html_footer(io)
      io.puts <<~HTML
          </div>
        </body>
        </html>
      HTML
    end
  end
end
