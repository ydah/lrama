# frozen_string_literal: true

RSpec.describe Lrama::Diagram do
  let(:out) { StringIO.new }
  let(:grammar_file_path) { fixture_path("common/basic.y") }
  let(:text) { File.read(grammar_file_path) }
  let(:grammar) do
    grammar = Lrama::Parser.new(text, grammar_file_path).parse
    grammar.prepare
    grammar.validate!
    grammar
  end
  let(:states) do
    states = Lrama::States.new(grammar, Lrama::Tracer.new($stderr))
    states.compute
    states
  end

  describe ".render_railroad" do
    it "renders a railroad diagram" do
      expect { Lrama::Diagram.render_railroad(out: out, grammar: grammar) }.not_to raise_error
      expect(out.string).to include('<h2 class="diagram-header">$accept</h2>')
      expect(out.string).to include('<h2 class="diagram-header">unused</h2>')
      expect(out.string).to include("<svg")
    end
  end

  describe ".render_states" do
    it "renders a state diagram in HTML format" do
      result = Lrama::Diagram.render_states(states, format: :html)
      expect(result).to be_a(String)
      expect(result).to include("mermaid")
    end

    it "renders a state diagram in mermaid format" do
      result = Lrama::Diagram.render_states(states, format: :mermaid)
      expect(result).to be_a(String)
      expect(result).to include("stateDiagram-v2")
    end
  end

  describe ".render_states_to_file" do
    it "renders a state diagram to file" do
      require 'tempfile'
      Tempfile.create(['states', '.html']) do |f|
        result = Lrama::Diagram.render_states_to_file(states, f.path)
        expect(result).to eq(f.path)
        expect(File.read(f.path)).to include("mermaid")
      end
    end
  end

  describe ".require_railroad_diagrams" do
    it "returns true if railroad_diagrams is available" do
      expect(Lrama::Diagram.require_railroad_diagrams).to be true
    end
  end

  describe ".require_state_diagram" do
    it "returns true if automograph is available" do
      expect(Lrama::Diagram.require_state_diagram).to be true
    end
  end

  describe "Lrama::Diagram::Railroad" do
    let(:railroad) { Lrama::Diagram::Railroad.new(grammar) }

    before do
      Lrama::Diagram::Railroad.require!
    end

    describe "#render" do
      it "renders a railroad diagram" do
        expect { railroad.render(out: out) }.not_to raise_error
        expect(out.string).to include('<h2 class="diagram-header">$accept</h2>')
        expect(out.string).to include('<h2 class="diagram-header">unused</h2>')
        expect(out.string).to include("<svg")
      end
    end

    describe "#default_style" do
      it "returns the default style" do
        expect(railroad.default_style).to eq RailroadDiagrams::Style::default_style
      end
    end

    describe "#diagrams" do
      it "returns diagrams" do
        result = railroad.diagrams
        expect(result).to include('<h2 class="diagram-header">$accept</h2>')
        expect(result).to include('<h2 class="diagram-header">unused</h2>')
        expect(result).to include("<svg")
      end
    end

    describe ".available?" do
      it "returns true when railroad_diagrams is available" do
        expect(Lrama::Diagram::Railroad.available?).to be true
      end
    end

    describe ".require!" do
      it "requires railroad_diagrams without error" do
        expect { Lrama::Diagram::Railroad.require! }.not_to raise_error
      end
    end
  end

  describe "Lrama::Diagram::States" do
    let(:states_diagram) { Lrama::Diagram::States.new(states) }

    before do
      Lrama::Diagram::States.require!
    end

    describe "#render" do
      it "renders in HTML format" do
        result = states_diagram.render(format: :html)
        expect(result).to be_a(String)
        expect(result).to include("mermaid")
      end

      it "renders in mermaid format" do
        result = states_diagram.render(format: :mermaid)
        expect(result).to be_a(String)
        expect(result).to include("stateDiagram-v2")
      end

      it "renders with custom name" do
        result = states_diagram.render(format: :mermaid, name: "Custom Automaton")
        expect(result).to include("stateDiagram-v2")
      end
    end

    describe "#render_to_file" do
      it "renders to file" do
        require 'tempfile'
        Tempfile.create(['states', '.mmd']) do |f|
          result = states_diagram.render_to_file(f.path, format: :mermaid)
          expect(result).to eq(f.path)
          expect(File.read(f.path)).to include("stateDiagram-v2")
        end
      end
    end

    describe ".available?" do
      it "returns true when automograph is available" do
        expect(Lrama::Diagram::States.available?).to be true
      end
    end

    describe ".require!" do
      it "requires automograph without error" do
        expect { Lrama::Diagram::States.require! }.not_to raise_error
      end
    end
  end

  describe "Lrama::Diagram::StatesAdapter" do
    let(:adapter) { Lrama::Diagram::StatesAdapter.new(states) }

    describe "#build" do
      it "builds an Automograph::Model" do
        model = adapter.build
        expect(model).to be_a(Automograph::Model)
      end

      it "builds model with custom name" do
        model = adapter.build(name: "Custom Name")
        expect(model.name).to eq("Custom Name")
      end

      it "builds model with default name" do
        model = adapter.build
        expect(model.name).to eq("LALR(1) Automaton")
      end

      it "includes all states" do
        model = adapter.build
        expect(model.states.count).to eq(states.states.count)
      end

      it "includes transitions" do
        model = adapter.build
        expect(model.transitions).not_to be_empty
      end

      it "sets initial state" do
        model = adapter.build
        expect(model.initial_state_id).to eq(0)
      end
    end
  end
end
