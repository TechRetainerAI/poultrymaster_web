"use client";

import { useEffect, useMemo, useState } from "react";
import { getFarms, getFarmCount, type FarmSummary } from "@/lib/api/system";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Badge } from "@/components/ui/badge";
import { Skeleton } from "@/components/ui/skeleton";
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";

export default function SystemFarmsPage() {
  const [farms, setFarms] = useState<FarmSummary[]>([]);
  const [count, setCount] = useState<number>(0);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>("");
  const [sortKey, setSortKey] = useState<string | null>(null);
  const [sortDir, setSortDir] = useState<SortDirection>(null);
  const handleSort = (key: string) => {
    const r = toggleSort(key, sortKey, sortDir);
    setSortKey(r.key);
    setSortDir(r.direction);
  };

  useEffect(() => {
    let mounted = true;
    (async () => {
      try {
        setLoading(true);
        const [list, total] = await Promise.all([getFarms(), getFarmCount()]);
        if (!mounted) return;
        setFarms(list ?? []);
        setCount(total ?? 0);
      } catch (e) {
        setError(e instanceof Error ? e.message : "Failed to load farms");
      } finally {
        setLoading(false);
      }
    })();
    return () => {
      mounted = false;
    };
  }, []);

  const paidCount = useMemo(
    () => farms.filter((f) => f.hasPaidSubscription === true).length,
    [farms]
  );
  const unpaidCount = useMemo(
    () => farms.filter((f) => f.hasPaidSubscription !== true).length,
    [farms]
  );

  const sortedAll = useMemo(() => sortData(farms, sortKey, sortDir), [farms, sortKey, sortDir]);
  const sortedPaid = useMemo(
    () => sortData(farms.filter((f) => f.hasPaidSubscription === true), sortKey, sortDir),
    [farms, sortKey, sortDir]
  );
  const sortedUnpaid = useMemo(
    () => sortData(farms.filter((f) => f.hasPaidSubscription !== true), sortKey, sortDir),
    [farms, sortKey, sortDir]
  );

  function FarmTable({ rows, emptyLabel }: { rows: FarmSummary[]; emptyLabel: string }) {
    return (
      <div className="overflow-x-auto">
        <Table>
          <TableHeader>
            <TableRow>
              <SortableHeader label="Farm name" sortKey="farmName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
              <SortableHeader label="Farm ID" sortKey="farmId" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
              <SortableHeader label="Subscription" sortKey="hasPaidSubscription" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
              <SortableHeader label="Users" sortKey="totalUsers" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" />
              <SortableHeader label="Staff" sortKey="staffCount" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className="text-right" />
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow>
                <TableCell colSpan={5} className="text-center text-sm text-muted-foreground">
                  {emptyLabel}
                </TableCell>
              </TableRow>
            ) : (
              rows.map((f) => (
                <TableRow key={f.farmId}>
                  <TableCell className="font-medium">{f.farmName || "(No name)"}</TableCell>
                  <TableCell className="text-muted-foreground font-mono text-xs">{f.farmId}</TableCell>
                  <TableCell>
                    {f.hasPaidSubscription === true ? (
                      <Badge className="bg-emerald-600 hover:bg-emerald-600">Subscribed</Badge>
                    ) : (
                      <Badge variant="secondary">Not subscribed</Badge>
                    )}
                  </TableCell>
                  <TableCell className="text-right">{f.totalUsers}</TableCell>
                  <TableCell className="text-right">{f.staffCount}</TableCell>
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>
    );
  }

  return (
    <div className="p-4 md:p-6 space-y-6">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">System farms</h1>
          <p className="text-sm text-muted-foreground">
            Registered farms, subscription status (paid flag on any farm user), and headcounts.
          </p>
        </div>
        <Badge variant="secondary">Platform owner only</Badge>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-muted-foreground">Registered farms</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? <Skeleton className="h-8 w-20" /> : <div className="text-3xl font-bold">{count}</div>}
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-muted-foreground">Subscribed (paid)</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? <Skeleton className="h-8 w-20" /> : <div className="text-3xl font-bold text-emerald-700">{paidCount}</div>}
          </CardContent>
        </Card>
        <Card>
          <CardHeader className="pb-2">
            <CardTitle className="text-sm text-muted-foreground">Not subscribed</CardTitle>
          </CardHeader>
          <CardContent>
            {loading ? <Skeleton className="h-8 w-20" /> : <div className="text-3xl font-bold text-amber-800">{unpaidCount}</div>}
          </CardContent>
        </Card>
      </div>

      <Card>
        <CardHeader className="space-y-1">
          <CardTitle>Farm directory</CardTitle>
        </CardHeader>
        <CardContent>
          {error && <div className="text-sm text-red-600 mb-3">{error}</div>}
          {loading ? (
            <div className="space-y-2">
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-8 w-full" />
              <Skeleton className="h-8 w-full" />
            </div>
          ) : (
            <Tabs defaultValue="all" className="w-full">
              <TabsList className="grid w-full max-w-lg grid-cols-3">
                <TabsTrigger value="all">All ({farms.length})</TabsTrigger>
                <TabsTrigger value="paid">Paid ({paidCount})</TabsTrigger>
                <TabsTrigger value="unpaid">Unpaid ({unpaidCount})</TabsTrigger>
              </TabsList>
              <TabsContent value="all" className="mt-4">
                <FarmTable rows={sortedAll} emptyLabel="No farms found." />
              </TabsContent>
              <TabsContent value="paid" className="mt-4">
                <FarmTable rows={sortedPaid} emptyLabel="No farms with an active subscription flag." />
              </TabsContent>
              <TabsContent value="unpaid" className="mt-4">
                <FarmTable rows={sortedUnpaid} emptyLabel="All farms are marked subscribed." />
              </TabsContent>
            </Tabs>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
