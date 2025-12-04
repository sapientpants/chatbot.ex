defmodule Chatbot.RAG.MarkdownChunker do
  @moduledoc """
  Markdown-aware text chunking that respects document structure.

  Chunks are split on:
  1. Markdown headers (##, ###, etc.)
  2. Paragraph boundaries
  3. Code block boundaries

  Maintains context by including parent headers in metadata.

  ## Configuration

  - `chunk_size` - Target characters per chunk (default: 2000, ~500 tokens)
  - `chunk_overlap` - Overlap characters between chunks (default: 200, ~50 tokens)
  - `min_chunk_size` - Minimum chunk size to avoid tiny fragments (default: 400)
  """

  @default_chunk_size 2000
  @default_chunk_overlap 200
  @default_min_chunk_size 400

  @type chunk :: %{
          content: String.t(),
          index: non_neg_integer(),
          metadata: %{
            headers: [String.t()],
            section_path: String.t(),
            start_line: non_neg_integer(),
            end_line: non_neg_integer()
          },
          content_hash: String.t()
        }

  @doc """
  Chunks markdown content into smaller pieces while respecting document structure.

  ## Options

    * `:chunk_size` - Target chunk size in characters (default: #{@default_chunk_size})
    * `:chunk_overlap` - Overlap between chunks in characters (default: #{@default_chunk_overlap})
    * `:min_chunk_size` - Minimum chunk size (default: #{@default_min_chunk_size})
    * `:filename` - Original filename for metadata (optional)

  ## Returns

  A list of chunk maps containing content, index, metadata, and content_hash.
  """
  @spec chunk(String.t(), keyword()) :: [chunk()]
  def chunk(markdown_content, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, config(:chunk_size, @default_chunk_size))

    chunk_overlap =
      Keyword.get(opts, :chunk_overlap, config(:chunk_overlap, @default_chunk_overlap))

    min_chunk_size =
      Keyword.get(opts, :min_chunk_size, config(:min_chunk_size, @default_min_chunk_size))

    filename = Keyword.get(opts, :filename)

    markdown_content
    |> split_into_sections()
    |> Enum.flat_map(&split_section_into_chunks(&1, chunk_size, chunk_overlap, min_chunk_size))
    |> merge_small_chunks(min_chunk_size)
    |> Enum.with_index()
    |> Enum.map(fn {section, index} ->
      build_chunk(section, index, filename)
    end)
  end

  # Split markdown into sections based on headers
  defp split_into_sections(content) do
    lines = String.split(content, "\n")
    {accumulated_sections, current} = Enum.reduce(lines, {[], nil}, &accumulate_section/2)

    # Don't forget the last section
    final_sections = if current, do: [current | accumulated_sections], else: accumulated_sections

    final_sections
    |> Enum.reverse()
    |> Enum.filter(fn section -> String.trim(section.content) != "" end)
  end

  defp accumulate_section(line, {sections, nil}) do
    # Start first section
    headers = extract_headers(line)

    section = %{
      content: line,
      headers: headers,
      start_line: 1
    }

    {sections, section}
  end

  defp accumulate_section(line, {sections, current}) do
    if header?(line) do
      # Start new section, save current
      new_headers = update_headers(current.headers, line)

      new_section = %{
        content: line,
        headers: new_headers,
        start_line: current.start_line + count_lines(current.content)
      }

      {[current | sections], new_section}
    else
      # Continue current section
      updated = %{current | content: current.content <> "\n" <> line}
      {sections, updated}
    end
  end

  defp header?(line) do
    String.match?(line, ~r/^\#{1,6}\s+/)
  end

  defp extract_headers(line) do
    if header?(line), do: [extract_header_text(line)], else: []
  end

  defp extract_header_text(line) do
    line
    |> String.replace(~r/^#+\s*/, "")
    |> String.trim()
  end

  defp header_level(line) do
    case Regex.run(~r/^(#+)/, line) do
      [_match, hashes] -> String.length(hashes)
      _no_match -> 0
    end
  end

  defp update_headers(current_headers, new_header_line) do
    level = header_level(new_header_line)
    header_text = extract_header_text(new_header_line)

    # Keep headers at higher levels (smaller numbers), replace at same or lower
    kept =
      current_headers
      |> Enum.with_index(1)
      |> Enum.filter(fn {_h, i} -> i < level end)
      |> Enum.map(fn {h, _i} -> h end)

    Enum.reverse([header_text | Enum.reverse(kept)])
  end

  defp count_lines(content) do
    content
    |> String.split("\n")
    |> length()
  end

  # Split a section into chunks if it exceeds the size limit
  defp split_section_into_chunks(section, chunk_size, chunk_overlap, _min_chunk_size) do
    content = section.content

    if String.length(content) <= chunk_size do
      [section]
    else
      # Split on paragraph boundaries
      paragraphs = String.split(content, ~r/\n\n+/)
      chunk_paragraphs(paragraphs, section, chunk_size, chunk_overlap)
    end
  end

  defp chunk_paragraphs(paragraphs, section, chunk_size, overlap) do
    {chunks, current_chunk, _line_offset} =
      Enum.reduce(paragraphs, {[], "", 0}, fn para, {chunks, current, offset} ->
        candidate = if current == "", do: para, else: current <> "\n\n" <> para

        if String.length(candidate) > chunk_size and current != "" do
          # Start new chunk with overlap
          overlap_text = get_overlap_text(current, overlap)
          new_current = overlap_text <> para
          new_offset = offset + count_lines(current)

          chunk = %{section | content: current, start_line: section.start_line + offset}
          {[chunk | chunks], new_current, new_offset}
        else
          {chunks, candidate, offset}
        end
      end)

    # Add final chunk
    final_chunks =
      if current_chunk != "" do
        chunk = %{section | content: current_chunk}
        [chunk | chunks]
      else
        chunks
      end

    Enum.reverse(final_chunks)
  end

  defp get_overlap_text(text, overlap_size) do
    if String.length(text) <= overlap_size do
      text
    else
      text
      |> String.slice(-overlap_size, overlap_size)
      |> String.replace(~r/^[^\s]*\s/, "")
    end
  end

  # Merge chunks that are too small
  defp merge_small_chunks(sections, min_size) do
    {accumulated, pending} =
      Enum.reduce(sections, {[], nil}, fn section, {acc, pending_section} ->
        cond do
          pending_section == nil ->
            if String.length(section.content) < min_size do
              {acc, section}
            else
              {[section | acc], nil}
            end

          String.length(pending_section.content) + String.length(section.content) < min_size * 2 ->
            # Merge with pending
            merged_section = %{
              pending_section
              | content: pending_section.content <> "\n\n" <> section.content,
                headers: pending_section.headers
            }

            {acc, merged_section}

          true ->
            # Output pending, maybe hold section
            if String.length(section.content) < min_size do
              {[pending_section | acc], section}
            else
              {[section, pending_section | acc], nil}
            end
        end
      end)

    # Don't forget pending
    final_list = if pending, do: [pending | accumulated], else: accumulated

    Enum.reverse(final_list)
  end

  defp build_chunk(section, index, filename) do
    content = String.trim(section.content)
    end_line = section.start_line + count_lines(content) - 1

    section_path = Enum.join(section.headers, " > ")

    base_metadata = %{
      headers: section.headers,
      section_path: section_path,
      start_line: section.start_line,
      end_line: end_line
    }

    metadata = if filename, do: Map.put(base_metadata, :filename, filename), else: base_metadata

    content_hash = Base.encode16(:crypto.hash(:sha256, content), case: :lower)

    %{
      content: content,
      index: index,
      metadata: metadata,
      content_hash: content_hash
    }
  end

  defp config(key, default) do
    rag_config = Application.get_env(:chatbot, :rag, [])
    Keyword.get(rag_config, key, default)
  end
end
