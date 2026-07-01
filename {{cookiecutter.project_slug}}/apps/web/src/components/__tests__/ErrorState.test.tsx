import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { ErrorState } from "@/components/ErrorState";
import { ApiError } from "@/lib/api/client";

describe("ErrorState", () => {
  it("renders the message and correlation id for an ApiError", () => {
    const error = new ApiError(502, "upstream_error", "AI service failed", "corr-123");
    render(<ErrorState error={error} />);

    expect(screen.getByRole("alert")).toHaveTextContent("AI service failed");
    expect(screen.getByText(/corr-123/)).toBeInTheDocument();
  });

  it("falls back to a generic message for unknown errors", () => {
    render(<ErrorState error={"boom"} />);
    expect(screen.getByRole("alert")).toHaveTextContent("Something went wrong.");
  });

  it("calls onRetry when the retry button is clicked", async () => {
    const onRetry = vi.fn();
    render(<ErrorState error={new Error("nope")} onRetry={onRetry} />);

    await userEvent.click(screen.getByRole("button", { name: /retry/i }));
    expect(onRetry).toHaveBeenCalledOnce();
  });
});
