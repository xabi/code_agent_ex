defprotocol CodeAgentEx.LLMFormattable do
  @moduledoc """
  Protocol for formatting values for LLM consumption.

  This protocol allows different types to define how they should be
  represented when sent to the LLM in observations.
  """

  @doc """
  Formats a value for LLM consumption.

  Returns a string representation suitable for the LLM to understand.
  """
  @spec to_llm_string(t) :: String.t()
  def to_llm_string(value)
end

# Implementation for tuples representing media files
defimpl CodeAgentEx.LLMFormattable, for: Tuple do
  def to_llm_string({:image, path}) when is_binary(path), do: "image: #{path}"
  def to_llm_string({:video, path}) when is_binary(path), do: "video: #{path}"
  def to_llm_string({:audio, path}) when is_binary(path), do: "audio: #{path}"
  def to_llm_string(tuple), do: inspect(tuple)
end

# Implementation for strings (pass through)
defimpl CodeAgentEx.LLMFormattable, for: BitString do
  def to_llm_string(string), do: string
end

# Implementation for numbers
defimpl CodeAgentEx.LLMFormattable, for: Integer do
  def to_llm_string(int), do: Integer.to_string(int)
end

defimpl CodeAgentEx.LLMFormattable, for: Float do
  def to_llm_string(float), do: Float.to_string(float)
end

# Implementation for atoms
defimpl CodeAgentEx.LLMFormattable, for: Atom do
  def to_llm_string(nil), do: "nil"
  def to_llm_string(true), do: "true"
  def to_llm_string(false), do: "false"
  def to_llm_string(atom), do: Atom.to_string(atom)
end

# Implementation for lists
defimpl CodeAgentEx.LLMFormattable, for: List do
  def to_llm_string(list), do: inspect(list)
end

# Implementation for maps
defimpl CodeAgentEx.LLMFormattable, for: Map do
  def to_llm_string(map), do: inspect(map)
end

# Fallback implementation for any other type
defimpl CodeAgentEx.LLMFormattable, for: Any do
  def to_llm_string(value), do: inspect(value)
end
