defmodule Shepherd.Bao do
  @moduledoc """
  Thin Bao HTTP client. Reads `BAO_ADDR` and `BAO_TOKEN` from env; falls
  back to `~/.bao-token` for the token so the CLI still works after a
  fresh `bao login` in a sibling shell.

  This module wraps only what the shepherd commands need: cert-auth CRUD,
  KV v2 read/write, PKI sign/revoke, identity groups. It is deliberately
  small — anything else drops through to `Req` directly at the call site
  so surprises stay near their handlers.
  """

  # No default: RFD 2195 puts Bao on the tailnet at
  # https://weftspun-bao.<tailnet>.ts.net:8200, and a guessed host fails
  # slower and less clearly than an unset variable.

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

  # PKI ------------------------------------------------------------------

  def pki_sign(role, csr_pem, ttl \\ "8760h") do
    post("pki_int/sign/#{role}", %{csr: csr_pem, ttl: ttl})
  end

  def pki_revoke(serial) do
    post("pki_int/revoke", %{serial_number: serial})
  end

  # Cert-auth ------------------------------------------------------------

  def cert_auth_write(name, cert_pem, policies, ttl \\ "8h") do
    post("auth/cert/certs/#{name}", %{
      certificate: cert_pem,
      display_name: name,
      token_policies: policies,
      token_ttl: ttl
    })
  end

  def cert_auth_delete(name), do: delete("auth/cert/certs/#{name}")

  # Identity groups ------------------------------------------------------

  def group_add(group_id, entity_ids) do
    post("identity/group/id/#{group_id}", %{member_entity_ids: entity_ids})
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
      nil -> read_token_file()
      "" -> read_token_file()
      t -> t
    end
  end

  defp read_token_file do
    path = Path.expand("~/.bao-token")
    case File.read(path) do
      {:ok, t} -> String.trim(t)
      _ -> raise "no BAO_TOKEN in env and no #{path}; run `bao login` first"
    end
  end

  defp ca_bundle, do: System.get_env("BAO_CACERT", "/etc/ssl/cert.pem")
end
