{ lib }:
{
  mergeUnique = lists:
    lib.unique (lib.concatLists (lib.filter (list: list != null) lists));
}
