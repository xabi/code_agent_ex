defmodule CodeAgentEx.Tools.FinanceTools do
  @moduledoc """
  Outils financiers utilisant yfinance via Pythonx pour le CodeAgent.

  Permet de récupérer des données financières en temps réel depuis Yahoo Finance.
  """

  require Logger

  @doc """
  Tool pour récupérer le prix actuel d'une action.
  """
  def stock_price do
    %CodeAgentEx.Tool{
      name: :stock_price,
      description: "Gets current stock price and basic info. Call with: tools.stock_price.(ticker) e.g. stock_price.('AAPL')",
      inputs: %{
        "ticker" => %{type: "string", description: "Stock ticker symbol (e.g., 'AAPL', 'GOOGL', 'TSLA')"}
      },
      output_type: "string",
      function: &do_stock_price/1
    }
  end

  defp do_stock_price(ticker) do
    ticker = normalize_arg(ticker)

    python_code = """
    import yfinance as yf

    try:
        ticker_str = ticker.decode('utf-8')
        ticker_obj = yf.Ticker(ticker_str)
        info = ticker_obj.info

        current_price = info.get('currentPrice') or info.get('regularMarketPrice')
        previous_close = info.get('previousClose')
        company_name = info.get('longName') or info.get('shortName')
        currency = info.get('currency', 'USD')
        market_cap = info.get('marketCap')

        if current_price is None:
            output = ("error", "Unable to get price for this ticker")
        else:
            change = None
            change_percent = None
            if previous_close and previous_close > 0:
                change = current_price - previous_close
                change_percent = (change / previous_close) * 100

            result = f"{company_name} ({ticker_str}): {current_price:.2f} {currency}"

            if change is not None:
                sign = "+" if change >= 0 else ""
                result += f" ({sign}{change:.2f}, {sign}{change_percent:.2f}%)"

            if market_cap:
                result += f" | Market Cap: {market_cap:,} {currency}"

            output = ("ok", result)
    except Exception as e:
        output = ("error", str(e))

    output
    """

    try do
      {result, _globals} = Pythonx.eval(python_code, %{"ticker" => ticker})

      case Pythonx.decode(result) do
        {"ok", message} ->
          Logger.info("[FinanceTools] ✅ #{message}")
          message

        {"error", error_msg} ->
          "Error: #{error_msg}"
      end
    rescue
      error -> "Pythonx error: #{inspect(error)}"
    end
  end

  @doc """
  Tool pour récupérer l'historique des prix.
  """
  def stock_history do
    %CodeAgentEx.Tool{
      name: "stock_history",
      description: "Gets stock price history. Call with: tools.stock_history.(ticker, period). Periods: '1d', '5d', '1mo', '3mo', '6mo', '1y', '2y', '5y', 'ytd', 'max'",
      inputs: %{
        "ticker" => %{type: "string", description: "Stock ticker symbol"},
        "period" => %{type: "string", description: "History period (default: '1mo')"}
      },
      output_type: "string",
      function: &do_stock_history/2
    }
  end

  defp do_stock_history(ticker, period) do
    ticker = normalize_arg(ticker)
    period = normalize_arg(period)
    period = if period == "", do: "1mo", else: period

    python_code = """
    import yfinance as yf

    try:
        ticker_str = ticker.decode('utf-8')
        period_str = period.decode('utf-8')

        ticker_obj = yf.Ticker(ticker_str)
        hist = ticker_obj.history(period=period_str)

        if hist.empty:
            output = ("error", "No data available for this period")
        else:
            first_date = hist.index[0].strftime('%Y-%m-%d')
            last_date = hist.index[-1].strftime('%Y-%m-%d')
            first_price = hist['Close'].iloc[0]
            last_price = hist['Close'].iloc[-1]
            change = last_price - first_price
            change_percent = (change / first_price) * 100

            min_price = hist['Low'].min()
            max_price = hist['High'].max()
            avg_volume = hist['Volume'].mean()

            result = f"History {ticker_str} ({first_date} → {last_date}):\\n"
            result += f"Start: {first_price:.2f} → End: {last_price:.2f}\\n"
            result += f"Change: {change:+.2f} ({change_percent:+.2f}%)\\n"
            result += f"Min: {min_price:.2f} | Max: {max_price:.2f}\\n"
            result += f"Avg Volume: {avg_volume:,.0f}"

            output = ("ok", result)
    except Exception as e:
        output = ("error", str(e))

    output
    """

    try do
      {result, _globals} = Pythonx.eval(python_code, %{"ticker" => ticker, "period" => period})

      case Pythonx.decode(result) do
        {"ok", message} ->
          Logger.info("[FinanceTools] ✅ History retrieved")
          message

        {"error", error_msg} ->
          "Error: #{error_msg}"
      end
    rescue
      error -> "Pythonx error: #{inspect(error)}"
    end
  end

  @doc """
  Tool pour récupérer les informations d'une entreprise.
  """
  def stock_info do
    %CodeAgentEx.Tool{
      name: "stock_info",
      description: "Gets detailed company information. Call with: tools.stock_info.(ticker)",
      inputs: %{
        "ticker" => %{type: "string", description: "Stock ticker symbol"}
      },
      output_type: "string",
      function: &do_stock_info/1
    }
  end

  defp do_stock_info(ticker) do
    ticker = normalize_arg(ticker)

    python_code = """
    import yfinance as yf

    try:
        ticker_str = ticker.decode('utf-8')
        ticker_obj = yf.Ticker(ticker_str)
        info = ticker_obj.info

        company_name = info.get('longName', 'N/A')
        sector = info.get('sector', 'N/A')
        industry = info.get('industry', 'N/A')
        country = info.get('country', 'N/A')
        employees = info.get('fullTimeEmployees', 'N/A')
        website = info.get('website', 'N/A')
        summary = info.get('longBusinessSummary', 'N/A')

        pe_ratio = info.get('trailingPE', 'N/A')
        dividend_yield = info.get('dividendYield', 'N/A')
        if dividend_yield != 'N/A' and dividend_yield:
            dividend_yield = f"{dividend_yield * 100:.2f}%"

        result = f"{company_name} ({ticker_str})\\n"
        result += f"Sector: {sector} | Industry: {industry}\\n"
        result += f"Country: {country} | Employees: {employees}\\n"
        result += f"Website: {website}\\n"
        result += f"P/E Ratio: {pe_ratio} | Dividend Yield: {dividend_yield}\\n"
        result += f"\\nDescription: {summary[:300]}..." if len(str(summary)) > 300 else f"\\nDescription: {summary}"

        output = ("ok", result)
    except Exception as e:
        output = ("error", str(e))

    output
    """

    try do
      {result, _globals} = Pythonx.eval(python_code, %{"ticker" => ticker})

      case Pythonx.decode(result) do
        {"ok", message} ->
          Logger.info("[FinanceTools] ✅ Info retrieved")
          message

        {"error", error_msg} ->
          "Error: #{error_msg}"
      end
    rescue
      error -> "Pythonx error: #{inspect(error)}"
    end
  end

  @doc """
  Tool pour comparer plusieurs actions.
  """
  def compare_stocks do
    %CodeAgentEx.Tool{
      name: "compare_stocks",
      description: "Compares multiple stocks (up to 5). Call with: tools.compare_stocks.(tickers) e.g. compare_stocks.('AAPL,GOOGL,MSFT')",
      inputs: %{
        "tickers" => %{type: "string", description: "Comma-separated list of tickers"}
      },
      output_type: "string",
      function: &do_compare_stocks/1
    }
  end

  defp do_compare_stocks(tickers) do
    tickers = normalize_arg(tickers)

    python_code = """
    import yfinance as yf

    try:
        tickers_str = tickers.decode('utf-8')
        tickers_list = [t.strip() for t in tickers_str.split(',')]

        if len(tickers_list) > 5:
            output = ("error", "Maximum 5 stocks can be compared at once")
        else:
            results = []

            for ticker_symbol in tickers_list:
                try:
                    ticker_obj = yf.Ticker(ticker_symbol)
                    info = ticker_obj.info

                    name = info.get('shortName', ticker_symbol)
                    current_price = info.get('currentPrice') or info.get('regularMarketPrice')
                    previous_close = info.get('previousClose')

                    if current_price and previous_close:
                        change = current_price - previous_close
                        change_percent = (change / previous_close) * 100
                        results.append(f"{name} ({ticker_symbol}): {current_price:.2f} ({change:+.2f}, {change_percent:+.2f}%)")
                    else:
                        results.append(f"{ticker_symbol}: Data not available")
                except:
                    results.append(f"{ticker_symbol}: Retrieval error")

            result_text = "Stock Comparison:\\n" + "\\n".join(results)
            output = ("ok", result_text)
    except Exception as e:
        output = ("error", str(e))

    output
    """

    try do
      {result, _globals} = Pythonx.eval(python_code, %{"tickers" => tickers})

      case Pythonx.decode(result) do
        {"ok", message} ->
          Logger.info("[FinanceTools] ✅ Comparison done")
          message

        {"error", error_msg} ->
          "Error: #{error_msg}"
      end
    rescue
      error -> "Pythonx error: #{inspect(error)}"
    end
  end

  @doc """
  Retourne tous les tools finance + final_answer.
  """
  def all_tools do
    [
      stock_price(),
      stock_history(),
      stock_info(),
      compare_stocks(),
      CodeAgentEx.Tool.final_answer()
    ]
  end

  # Normalise les charlists en binaries
  defp normalize_arg(arg) when is_list(arg), do: List.to_string(arg)
  defp normalize_arg(arg), do: arg
end
