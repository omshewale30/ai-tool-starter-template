import Link from "next/link";

export default function DashboardPage() {
  return (
    <>
      <h1>Dashboard</h1>
      <p className="muted">
        Welcome to {"{{ cookiecutter.project_name }}"}. This starter wires up auth, a typed API
        client, and a backend-mediated AI assistant.
      </p>

      <div className="card">
        <h2>Assistant</h2>
        <p className="muted">Send a prompt to the AI assistant (via the backend).</p>
        <Link className="btn" href="/chat">
          Open assistant
        </Link>
      </div>

      <div className="card">
        <h2>Your profile</h2>
        <p className="muted">
          View the identity and roles the backend sees for your access token.
        </p>
        <Link className="btn btn-secondary" href="/profile">
          View profile
        </Link>
      </div>
    </>
  );
}
