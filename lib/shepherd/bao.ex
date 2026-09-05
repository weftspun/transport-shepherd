defmodule Shepherd.Bao do
  @moduledoc """
  Thin Bao HTTP client. Reads `BAO_ADDR` and `BAO_TOKEN` from env. Never
  reads `~/.bao-token`: on a shared-`$HOME` box it is one file for every
  agent (RFD 2195 DETAILS §"stale token file").

  Wraps only what `status` and `gates` need: raw HTTP verbs plus KV v2
  read/write. The PKI, cert-auth and identity-group calls were trimmed
  after the enrol/rotate/migrate/revoke ceremony went; if those calls
  are needed again, retrofit from RFD 2195 DETAILS §"stale token file"
  (same pointer `lib/shepherd/cli.ex` already names).
  """

  # HTTP -----------------------------------------------------------------

  def get(path), do: request(:get, path, nil)
  def list(path), do: request(:get, path <> "?list=true", nil)
  def put(path, body), do: request(:put, path, body)
  def post(path, body), do: request(:post, path, body)
  def delete(path), do: request(:delete, path, nil)

  defp request(method, path, body) do
    Req.request(
      method: method,
      url: addr() <> "/v1/" <> path,
      headers: [{"x-vault-token", token()}],
      json: body,
      connect_options: [transport_opts: [cacertfile: ca_bundle()]]
    )
  end

  # KV v2 ----------------------------------------------------------------

  def kv_get(mount, key) do
    with {:ok, %{status: 200, body: %{"data" => %{"data" => data}}}} <-
           get("#{mount}/data/#{key}") do
      {:ok, data}
    end
  end

  def kv_put(mount, key, data) do
    put("#{mount}/data/#{key}", %{data: data})
  end

  # Environment ----------------------------------------------------------

  defp addr do
    case System.get_env("BAO_ADDR") do
      nil -> raise "BAO_ADDR is unset; see RFD 2195 (https://weftspun-bao.<tailnet>.ts.net:8200)"
      "" -> raise "BAO_ADDR is empty; see RFD 2195 (https://weftspun-bao.<tailnet>.ts.net:8200)"
      a -> a
    end
  end

  defp token do
    case System.get_env("BAO_TOKEN") do
      nil -> raise token_error()
      "" -> raise token_error()
      t -> t
    end
  end

  defp token_error do
    "BAO_TOKEN is unset; login with -no-store into your per-agent " <>
      "credentials directory and export it (RFD 2195 DETAILS)"
  end

  defp ca_bundle, do: System.get_env("BAO_CACERT", "/etc/ssl/cert.pem")
end
