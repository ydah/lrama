# frozen_string_literal: true

require "open3"

RSpec.describe Lrama::OptionParser do
  describe "invalid argv" do
    context "when grammar file isn't specified" do
      it "returns stderr" do
        result = Open3.popen3("ruby", exe_path("lrama")) do |stdin, stdout, stderr, wait_thr|
          stderr.read
        end
        expect(result).to eq("File should be specified\n")
      end
    end

    context "when STDIN mode, but a grammar file isn't specified" do
      it "returns stderr" do
        result = Open3.popen3("ruby", exe_path("lrama"), "-") do |stdin, stdout, stderr, wait_thr|
          stderr.read
        end
        expect(result).to eq("File name for STDIN should be specified\n")
      end
    end
  end

  describe "version option" do
    it "print Lrama version and exit" do
      result = Open3.popen3("ruby", exe_path("lrama"), "--version") do |stdin, stdout, stderr, wait_thr|
        stdout.read
      end
      expect(result).to eq("lrama #{Lrama::VERSION}\n")
    end
  end

  describe "help option" do
    it "print help and exit" do
      ["--help", "-h"].each do |help|
        result = Open3.popen3("ruby", exe_path("lrama"), help) do |stdin, stdout, stderr, wait_thr|
          stdout.read
        end
        expect(result).to eq(<<~HELP)
          Lrama is LALR (1) parser generator written by Ruby.

          Usage: lrama [options] FILE

          STDIN mode:
          lrama [options] - FILE               read grammar from STDIN

          Tuning the Parser:
              -S, --skeleton=FILE              specify the skeleton to use
              -t, --debug                      display debugging outputs of internal parser
                                               same as '-Dparse.trace'
                  --locations                  enable location support
              -D, --define=NAME[=VALUE]        similar to '%define NAME VALUE'

          Output:
              -H, --header=[FILE]              also produce a header file named FILE
              -d                               also produce a header file
              -r, --report=REPORTS             also produce details on the automaton
                  --report-file=FILE           also produce details on the automaton output to a file named FILE
                  --report-mode=MODE           set report mode (default: text)
              -o, --output=FILE                leave output to FILE
                  --trace=TRACES               also output trace logs at runtime
                  --diagram=[FILE]             generate a diagram of the rules
                  --profile=PROFILES           profiles parser generation parts
              -v, --verbose                    same as '--report=state'

          Diagnostics:
              -W, --warnings                   report the warnings

          Error Recovery:
              -e                               enable error recovery

          Other options:
              -V, --version                    output version information and exit
              -h, --help                       display this help and exit

          REPORTS is a list of comma-separated words that can include:
              states                           describe the states
              itemsets                         complete the core item sets with their closure
              lookaheads                       explicitly associate lookahead tokens to items
              solved                           describe shift/reduce conflicts solving
              counterexamples, cex             generate conflict counterexamples
              rules                            list unused rules
              terms                            list unused terminals
              verbose                          report detailed internal state and analysis results
              all                              include all the above reports
              none                             disable all reports

          MODE is reported in one of the following formats:
              text                             plain text format
              html                             HTML format

          TRACES is a list of comma-separated words that can include:
              automaton                        display states
              closure                          display states
              rules                            display grammar rules
              only-explicit-rules              display only explicit grammar rules
              actions                          display grammar rules with actions
              time                             display generation time
              all                              include all the above traces
              none                             disable all traces

          PROFILES is a list of comma-separated words that can include:
              call-stack                       use sampling call-stack profiler (stackprof gem)
              memory                           use memory profiler (memory_profiler gem)

        HELP
      end
    end
  end

  describe "#validate_report" do
    let(:option_parser) { Lrama::OptionParser.new }

    context "when no options are passed" do
      it "returns option hash with grammar flag enabled" do
        opts = option_parser.send(:validate_report, [])
        expect(opts).to eq({grammar: true})
      end
    end

    context "when valid options are passed" do
      it "returns option hash" do
        opts = option_parser.send(:validate_report, ["states", "itemsets"])
        expect(opts).to eq({grammar: true, states: true, itemsets: true})
      end

      context "when cex is passed" do
        it "returns option hash counterexamples flag enabled" do
          opts = option_parser.send(:validate_report, ["cex"])
          expect(opts).to eq({grammar: true, counterexamples: true})
        end
      end

      context "when all is passed" do
        it "returns option hash all flags enabled" do
          opts = option_parser.send(:validate_report, ["all"])
          expect(opts).to eq({
            grammar: true, states: true, itemsets: true,
            lookaheads: true, solved: true, counterexamples: true,
            rules: true, terms: true, verbose: true
          })
        end
      end

      context "when none is passed" do
        it "returns empty option hash" do
          opts = option_parser.send(:validate_report, ["none"])
          expect(opts).to eq({})
        end
      end
    end

    describe "invalid options are passed" do
      it "returns option hash" do
        expect { option_parser.send(:validate_report, ["invalid"]) }.to raise_error(/Invalid report option/)
      end
    end

    context "when -v option is passed" do
      it "returns option hash states flag enabled" do
        opts = option_parser.send(:validate_report, ["states"])
        expect(opts).to eq({grammar: true, states: true})
      end
    end

    context "when --verbose option is passed" do
      it "returns option hash states flag enabled" do
        opts = option_parser.send(:validate_report, ["states"])
        expect(opts).to eq({grammar: true, states: true})
      end
    end
  end

  describe "#validate_trace" do
    let(:option_parser) { Lrama::OptionParser.new }

    context "when no options are passed" do
      it "returns empty option hash" do
        opts = option_parser.send(:validate_trace, [])
        expect(opts).to eq({})
      end
    end

    context "when valid options are passed" do
      let(:valid_traces) do
        %w[automaton closure rules only-explicit-rules actions time]
      end

      it "returns option hash" do
        opts = option_parser.send(:validate_trace, valid_traces)
        expect(opts).to eq({
          only_explicit_rules: true, actions: true, automaton: true, closure: true, rules: true, time: true
        })
      end

      context "when all is passed" do
        it "returns option hash all flags enabled" do
          opts = option_parser.send(:validate_trace, ["all"])
          expect(opts).to eq({
            automaton: true, closure: true, rules: true, actions: true, time: true
          })
        end
      end

      context "when none is passed" do
        it "returns empty option hash" do
          opts = option_parser.send(:validate_trace, ["none"])
          expect(opts).to eq({})
        end
      end
    end

    describe "invalid options are passed" do
      it "returns option hash" do
        expect { option_parser.send(:validate_trace, ["invalid"]) }.to raise_error(/Invalid trace option/)
      end
    end
  end

  describe "@grammar_file" do
    context "file is specified" do
      it "@grammar_file is file name" do
        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, [fixture_path("command/basic.y")])
        options = option_parser.instance_variable_get(:@options)
        expect(options.grammar_file).to match(/command\/basic\.y/)
      end
    end

    context "file name is specified after '-'" do
      it "@grammar_file is file name" do
        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, ["-", "test.y"])
        options = option_parser.instance_variable_get(:@options)
        expect(options.grammar_file).to eq "test.y"
      end
    end
  end

  describe "@outfile" do
    context "output option is not passed" do
      it "@outfile is default value" do
        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, ["-", "test.y"])
        options = option_parser.instance_variable_get(:@options)
        expect(options.outfile).to eq "y.tab.c"
      end
    end

    context "output option is passed" do
      it "@outfile is same with passed value" do
        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, ["-o", "parse.c", "-", "test.y"])
        options = option_parser.instance_variable_get(:@options)
        expect(options.outfile).to eq "parse.c"
      end
    end
  end

  describe "@header_file" do
    context "header file name is not passed" do
      context "outfile option is passed" do
        it "@header_file is set based on outfile" do
          option_parser = Lrama::OptionParser.new
          option_parser.send(:parse, ["-H", "-o", "parse.c", "-", "test.y"])
          options = option_parser.instance_variable_get(:@options)
          expect(options.header_file).to eq "./parse.h"
        end
      end

      context "outfile option is not passed" do
        it "@header_file is set based on outfile default value" do
          option_parser = Lrama::OptionParser.new
          option_parser.send(:parse, ["-H", "-", "test.y"])
          options = option_parser.instance_variable_get(:@options)
          expect(options.header_file).to eq "./y.tab.h"
        end
      end
    end

    context "header file name is passed" do
      it "@header_file is same with passed value" do
        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, ["-Hparse.h", "-", "test.y"])
        options = option_parser.instance_variable_get(:@options)
        expect(options.header_file).to eq "parse.h"
      end
    end
  end

  describe "@report_file" do
    context "report file name is not passed" do
      it "@report_file is set based on grammar file name" do
        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, ["--report=all", fixture_path("command/basic.y")])
        options = option_parser.instance_variable_get(:@options)
        expect(options.report_file).to match(/command\/basic\.output/)

        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, ["--report=all", "-", "test.y"])
        options = option_parser.instance_variable_get(:@options)
        expect(options.report_file).to eq "./test.output"
      end
    end

    context "report file name is passed" do
      it "@report_file is same with passed value" do
        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, ["--report-file=report.output", fixture_path("command/basic.y")])
        options = option_parser.instance_variable_get(:@options)
        expect(options.report_file).to eq "report.output"

        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, ["--report-file=report.output", "-", "test.y"])
        options = option_parser.instance_variable_get(:@options)
        expect(options.report_file).to eq "report.output"
      end
    end
  end

  describe "@warnings" do
    context "when warnings option is not passed" do
      it "returns false" do
        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, [fixture_path("command/basic.y")])
        options = option_parser.instance_variable_get(:@options)
        expect(options.warnings).to be false
      end
    end

    context "when warnings option is passed" do
      context "when --warnings is passed" do
        it "returns true" do
          option_parser = Lrama::OptionParser.new
          option_parser.send(:parse, ["--warnings", fixture_path("command/basic.y")])
          options = option_parser.instance_variable_get(:@options)
          expect(options.warnings).to be true
        end
      end

      context "when -W is passed" do
        it "returns true" do
          option_parser = Lrama::OptionParser.new
          option_parser.send(:parse, ["-W", fixture_path("command/basic.y")])
          options = option_parser.instance_variable_get(:@options)
          expect(options.warnings).to be true
        end
      end
    end
  end

  describe "@define" do
    context "when define option is not passed" do
      it "returns empty hash" do
        option_parser = Lrama::OptionParser.new
        option_parser.send(:parse, [fixture_path("command/basic.y")])
        options = option_parser.instance_variable_get(:@options)
        expect(options.define).to eq({})
      end
    end

    context "when define option is passed" do
      context "when value includes equal sign" do
        it "returns hash of define options" do
          option_parser = Lrama::OptionParser.new
          option_parser.send(:parse, ["--define=foo=1", fixture_path("command/basic.y")])
          options = option_parser.instance_variable_get(:@options)
          expect(options.define).to eq({'foo' => "1"})
        end
      end

      context "when value doesn't include equal sign" do
        it "returns hash of define options" do
          option_parser = Lrama::OptionParser.new
          option_parser.send(:parse, ["--define=foo", fixture_path("command/basic.y")])
          options = option_parser.instance_variable_get(:@options)
          expect(options.define).to eq({'foo' => nil})
        end
      end
    end
  end
end
