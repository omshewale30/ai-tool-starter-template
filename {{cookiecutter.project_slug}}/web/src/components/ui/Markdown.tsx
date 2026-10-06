import ReactMarkdown, { type Components } from "react-markdown";

// Links in model output open in a new tab without access to this window.
const COMPONENTS: Components = {
  a: ({ href, children }) => (
    <a href={href} target="_blank" rel="noopener noreferrer">
      {children}
    </a>
  ),
};

/**
 * Renders model output as Markdown. react-markdown never renders raw HTML, so model
 * output cannot inject markup or scripts.
 */
export function Markdown({ children }: { children: string }) {
  return (
    <div
      className={[
        "space-y-2 break-words",
        "[&_ol]:list-decimal [&_ol]:pl-5 [&_ul]:list-disc [&_ul]:pl-5",
        "[&_code]:rounded [&_code]:bg-page [&_code]:px-1 [&_code]:text-sm",
        "[&_pre]:overflow-x-auto [&_pre]:rounded-app [&_pre]:bg-page [&_pre]:p-3",
        "[&_table]:w-full [&_table]:text-sm [&_td]:border [&_td]:border-border [&_td]:px-2",
        "[&_th]:border [&_th]:border-border [&_th]:px-2 [&_th]:text-left",
        "[&_h1]:font-bold [&_h2]:font-semibold [&_h3]:font-semibold",
      ].join(" ")}
    >
      <ReactMarkdown components={COMPONENTS}>{children}</ReactMarkdown>
    </div>
  );
}
