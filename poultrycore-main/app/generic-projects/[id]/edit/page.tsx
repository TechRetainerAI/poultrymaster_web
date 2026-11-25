"use client"

import { useEffect, useState } from "react"
import { useParams } from "next/navigation"
import { Loader2, Pencil } from "lucide-react"
import { ProjectPage } from "@/components/generic/projects/project-page"
import { ProjectForm } from "@/components/generic/projects/project-form"
import { getProject, type GenericProject } from "@/lib/api/generic-projects"

export default function EditGenericProjectPage() {
  const { id } = useParams<{ id: string }>()
  const [project, setProject] = useState<GenericProject | null>(null)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    getProject(Number(id)).then(setProject).catch((e) => setError(e?.message ?? String(e)))
  }, [id])

  return (
    <ProjectPage title={project ? `Edit ${project.projectNumber}` : "Edit project"} icon={<Pencil className="h-5 w-5" />}
      wide={false} back={`/generic-projects/${id}`}>
      {error ? <p className="text-sm text-rose-600">{error}</p>
        : !project ? <Loader2 className="h-5 w-5 animate-spin text-slate-400" />
        : project.status === "Archived" ? <p className="text-sm text-slate-600">This project is archived. Restore it before editing.</p>
        : <ProjectForm project={project} />}
    </ProjectPage>
  )
}
