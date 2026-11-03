"""Flatten recorded JSON summaries into CSV; performs no planning or new inference."""
import argparse
import csv
import json

parser = argparse.ArgumentParser()
parser.add_argument("input_json")
parser.add_argument("output_csv")
args = parser.parse_args()
with open(args.input_json) as stream:
    run = json.load(stream)
rows = []
for summary in run["summaries"]:
    row = {key: value for key, value in summary.items() if key != "normalized_ci"}
    row.update(julia_threads=run["context"]["julia_threads"],
               source_commit=run["context"]["source_commit"],
               normalized_ci_lower=summary["normalized_ci"]["lower"],
               normalized_ci_upper=summary["normalized_ci"]["upper"],
               normalized_ci_method=summary["normalized_ci"]["method"])
    rows.append(row)
with open(args.output_csv, "w", newline="") as stream:
    writer = csv.DictWriter(stream, fieldnames=list(rows[0]), lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
print("SUMMARY_CSV_OK", len(rows), args.output_csv)
