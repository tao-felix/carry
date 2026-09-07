import { Section } from "./Section";

type Channel = "icloud" | "app";

/** The 12 sources of docs/DATA-CONTRACT.md §3, in contract order. */
const sources: {
  key: string;
  name: string;
  reads: string;
  channel: Channel;
  offByDefault?: boolean;
}[] = [
  { key: "photos", name: "Photos", reads: "New photos: time, place, caption. Text inside them with Pro.", channel: "icloud" },
  { key: "screenshots", name: "Screenshots", reads: "New screenshots. The text inside them with Pro.", channel: "icloud" },
  { key: "voice_memos", name: "Voice Memos", reads: "New recordings: title, length. Transcript with Pro.", channel: "icloud" },
  { key: "notes", name: "Notes", reads: "Notes edited today: title and text.", channel: "icloud" },
  { key: "messages", name: "Messages", reads: "iMessage and SMS threads active today.", channel: "icloud", offByDefault: true },
  { key: "calendar", name: "Calendar", reads: "Today's and upcoming events.", channel: "icloud" },
  { key: "reminders", name: "Reminders", reads: "Due, overdue and completed today.", channel: "icloud" },
  { key: "safari", name: "Safari", reads: "Pages visited today.", channel: "icloud", offByDefault: true },
  { key: "screen_time", name: "Screen Time", reads: "Apps used today and for how long.", channel: "icloud" },
  { key: "health", name: "Health", reads: "Sleep, steps, heart rate, HRV, workouts, weight, blood oxygen.", channel: "app" },
  { key: "location", name: "Location", reads: "Places visited: arrive, leave, where.", channel: "app" },
  { key: "inbox", name: "Share inbox", reads: "Anything you shared to Carry from any app.", channel: "app" },
];

function Badge({ channel }: { channel: Channel }) {
  const isCloud = channel === "icloud";
  return (
    <span
      className={`inline-flex h-6 items-center gap-1.5 rounded-full border px-2 font-mono text-[12px] leading-none ${
        isCloud ? "border-moss/40 text-moss" : "border-tangerine/40 text-tangerine"
      }`}
    >
      <span className={`h-1.5 w-1.5 rounded-full ${isCloud ? "bg-moss" : "bg-tangerine"}`} />
      {isCloud ? "via iCloud" : "via Carry app"}
    </span>
  );
}

export function Sources() {
  return (
    <Section
      id="sources"
      number="03"
      title="Sources"
      lede={
        <>
          Twelve sources. <span className="text-moss">Nine</span> arrive because iCloud already syncs them to your Mac;{" "}
          <span className="text-tangerine">three</span> only the Carry app can capture.
        </>
      }
    >
      <ul className="grid gap-px overflow-hidden rounded-card border border-line bg-line sm:grid-cols-2 lg:grid-cols-3">
        {sources.map((s) => (
          <li key={s.key} className="flex flex-col gap-3 bg-paper p-5">
            <div className="flex items-start justify-between gap-3">
              <h3 className="text-[17px] leading-[24px] font-medium text-ink">{s.name}</h3>
              <Badge channel={s.channel} />
            </div>
            <p className="text-[15px] leading-[22px] text-ink2">{s.reads}</p>
            {s.offByDefault ? (
              <p className="mt-auto font-mono text-[12px] leading-none text-warn">off by default</p>
            ) : null}
          </li>
        ))}
      </ul>
      <p className="mt-6 max-w-[720px] text-body text-ink2">
        <span className="text-ink">You choose on the phone.</span> The Mac reader obeys that choice, even for data
        already sitting on the Mac.
      </p>
    </Section>
  );
}
