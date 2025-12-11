defprotocol CodeAgentEx.LLMFormattable do
  @moduledoc """
  Protocol for formatting values for LLM consumption and media detection.

  This protocol allows different types to define:
  1. How they should be represented when sent to the LLM in observations
  2. Whether they represent media files (images, videos, audio, etc.)
  """

  @doc """
  Formats a value for LLM consumption.

  Returns a string representation suitable for the LLM to understand.
  """
  @spec to_llm_string(t) :: String.t()
  def to_llm_string(value)

  @doc """
  Determines if a value represents media and returns its type and path.

  Returns:
  - `{:media, media_type, path}` if the value is a media file (e.g., {:media, :images, "/path/to/file.png"})
  - `:not_media` if the value is not a media file

  The media_type should be a plural atom representing the category:
  - `:images` for image files
  - `:videos` for video files
  - `:audio` for audio files
  - `:documents` for document files
  - etc.
  """
  @spec media_type(t) :: {:media, atom(), String.t()} | :not_media
  def media_type(value)
end

# Implementation for tuples representing media files
defimpl CodeAgentEx.LLMFormattable, for: Tuple do
  def to_llm_string({:image, path}) when is_binary(path), do: "image: #{path}"
  def to_llm_string({:video, path}) when is_binary(path), do: "video: #{path}"
  def to_llm_string({:audio, path}) when is_binary(path), do: "audio: #{path}"
  def to_llm_string(tuple), do: inspect(tuple)

  def media_type({:image, path}) when is_binary(path), do: {:media, :images, path}
  def media_type({:video, path}) when is_binary(path), do: {:media, :videos, path}
  def media_type({:audio, path}) when is_binary(path), do: {:media, :audio, path}
  def media_type(_tuple), do: :not_media
end

# Implementation for strings (pass through)
defimpl CodeAgentEx.LLMFormattable, for: BitString do
  def to_llm_string(string), do: string
  def media_type(_string), do: :not_media
end

# Implementation for numbers
defimpl CodeAgentEx.LLMFormattable, for: Integer do
  def to_llm_string(int), do: Integer.to_string(int)
  def media_type(_int), do: :not_media
end

defimpl CodeAgentEx.LLMFormattable, for: Float do
  def to_llm_string(float), do: Float.to_string(float)
  def media_type(_float), do: :not_media
end

# Implementation for atoms
defimpl CodeAgentEx.LLMFormattable, for: Atom do
  def to_llm_string(nil), do: "nil"
  def to_llm_string(true), do: "true"
  def to_llm_string(false), do: "false"
  def to_llm_string(atom), do: Atom.to_string(atom)
  def media_type(_atom), do: :not_media
end

# Implementation for lists
defimpl CodeAgentEx.LLMFormattable, for: List do
  def to_llm_string(list), do: inspect(list)
  def media_type(_list), do: :not_media
end

# Implementation for maps
defimpl CodeAgentEx.LLMFormattable, for: Map do
  def to_llm_string(map), do: inspect(map)
  def media_type(_map), do: :not_media
end

# Fallback implementation for any other type
defimpl CodeAgentEx.LLMFormattable, for: Any do
  def to_llm_string(value), do: inspect(value)
  def media_type(_value), do: :not_media
end
