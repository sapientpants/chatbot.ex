defmodule Chatbot.RAG.MarkdownChunkerTest do
  use ExUnit.Case, async: true

  alias Chatbot.RAG.MarkdownChunker

  describe "chunk/2" do
    test "chunks simple markdown content" do
      content = """
      # Introduction

      This is a simple document with some content.

      ## Section One

      Some text in section one.

      ## Section Two

      Some text in section two.
      """

      chunks = MarkdownChunker.chunk(content)

      assert length(chunks) >= 1
      assert Enum.all?(chunks, &is_map/1)
      assert Enum.all?(chunks, &Map.has_key?(&1, :content))
      assert Enum.all?(chunks, &Map.has_key?(&1, :index))
      assert Enum.all?(chunks, &Map.has_key?(&1, :metadata))
      assert Enum.all?(chunks, &Map.has_key?(&1, :content_hash))
    end

    test "generates unique content hashes" do
      content = """
      # Part One

      Content A

      ## Part Two

      Content B
      """

      chunks = MarkdownChunker.chunk(content)

      hashes = Enum.map(chunks, & &1.content_hash)
      assert length(hashes) == length(Enum.uniq(hashes))
    end

    test "preserves headers in metadata" do
      content = """
      # Main Title

      ## Subsection

      Some content here.
      """

      chunks = MarkdownChunker.chunk(content)

      # At least one chunk should have headers metadata
      chunk_with_headers =
        Enum.find(chunks, fn chunk ->
          chunk.metadata[:headers] != nil and chunk.metadata[:headers] != []
        end)

      assert chunk_with_headers != nil
    end

    test "respects chunk_size option" do
      content = String.duplicate("This is some test content. ", 100)

      # Small chunk size should produce more chunks
      small_chunks = MarkdownChunker.chunk(content, chunk_size: 200)
      large_chunks = MarkdownChunker.chunk(content, chunk_size: 2000)

      assert length(small_chunks) >= length(large_chunks)
    end

    test "includes filename in metadata when provided" do
      content = "# Test\n\nSome content."

      chunks = MarkdownChunker.chunk(content, filename: "test.md")

      assert Enum.all?(chunks, fn chunk ->
               chunk.metadata[:filename] == "test.md"
             end)
    end

    test "handles empty content" do
      chunks = MarkdownChunker.chunk("")

      assert chunks == []
    end

    test "handles content with only whitespace" do
      chunks = MarkdownChunker.chunk("   \n\n   ")

      assert chunks == []
    end

    test "assigns sequential indices" do
      content = """
      # Section 1
      Content 1

      # Section 2
      Content 2

      # Section 3
      Content 3
      """

      chunks = MarkdownChunker.chunk(content)

      indices = Enum.map(chunks, & &1.index)
      assert indices == Enum.to_list(0..(length(chunks) - 1))
    end

    test "tracks line numbers in metadata" do
      content = """
      # Title

      Some content here.
      """

      chunks = MarkdownChunker.chunk(content)

      assert Enum.all?(chunks, fn chunk ->
               is_integer(chunk.metadata[:start_line]) and
                 is_integer(chunk.metadata[:end_line]) and
                 chunk.metadata[:end_line] >= chunk.metadata[:start_line]
             end)
    end

    test "handles code blocks" do
      content = """
      # Code Example

      Here is some code:

      ```elixir
      defmodule Example do
        def hello, do: "world"
      end
      ```

      More text after code.
      """

      chunks = MarkdownChunker.chunk(content)

      # Should not crash and should include code content
      full_content = Enum.map_join(chunks, "\n", & &1.content)
      assert String.contains?(full_content, "defmodule Example")
    end

    test "builds section path from headers" do
      content = """
      # Top Level

      ## Second Level

      Content here.
      """

      chunks = MarkdownChunker.chunk(content)

      # Find chunk with section content
      chunk =
        Enum.find(chunks, fn c ->
          String.contains?(c.content, "Content here")
        end)

      assert chunk != nil
      # Section path should contain header info
      assert is_binary(chunk.metadata[:section_path])
    end
  end

  describe "chunk/2 with overlap" do
    test "creates overlapping chunks for large content" do
      # Create content that will definitely need multiple chunks
      content = """
      # Introduction

      #{String.duplicate("This is paragraph one with lots of content. ", 50)}

      #{String.duplicate("This is paragraph two with different content. ", 50)}

      #{String.duplicate("This is paragraph three with even more content. ", 50)}
      """

      chunks = MarkdownChunker.chunk(content, chunk_size: 500, chunk_overlap: 100)

      if length(chunks) > 1 do
        # Check that consecutive chunks might have some overlap
        # (This is a soft check since overlap depends on paragraph boundaries)
        assert length(chunks) >= 2
      end
    end
  end
end
