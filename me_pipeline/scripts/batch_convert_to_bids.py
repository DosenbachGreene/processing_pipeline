from pathlib import Path
from argparse import ArgumentParser
from me_pipeline.scripts.convert_to_bids import main as convert_to_bids
from concurrent.futures import ProcessPoolExecutor
import csv


def main():
    parser = ArgumentParser()
    parser.add_argument("table", help="CSV table w/ path, subject, session")
    parser.add_argument("output_directory", help="The directory to output the BIDS datasets to.")
    parser.add_argument("dataset_name", help="The name of the dataset.")
    parser.add_argument("-n", "--num_threads", help="The number of threads to use.", default=1, type=int)

    # parse the arguments
    args = parser.parse_args()

    # read the csv table in
    with open(args.table, "r") as f:
        reader = csv.reader(f, delimiter=",")
        table = list(reader)

    # make the output directory's temp dirs to
    # prevent race conditions in concurrent mode
    (Path(args.output_directory) / ".temp").mkdir(parents=True, exist_ok=True)
    (Path(args.output_directory) / ".heudiconv").mkdir(parents=True, exist_ok=True)

    # loop and call convert_to_bids
    with ProcessPoolExecutor(max_workers=args.num_threads) as executor:
        futures = []
        for path, subject, session in table:
            futures.append(executor.submit(
                convert_to_bids,
                [
                    "--files",
                    path,
                    "-s",
                    subject,
                    "-ss",
                    session,
                    "--outdir",
                    str(Path(args.output_directory) / args.dataset_name),
                    "--converter",
                    "dcm2niix",
                    "-b",
                    "notop",
                    "--overwrite",
                ]
            ))

        # wait for all futures to complete
        for future in futures:
            future.result()
