"use client"

import { FolderPlus } from "lucide-react"
import { ProjectPage } from "@/components/generic/projects/project-page"
import { ProjectForm } from "@/components/generic/projects/project-form"

export default function NewGenericProjectPage() {
  return (
    <ProjectPage title="New project or contract" icon={<FolderPlus className="h-5 w-5" />} wide={false} back="/generic-projects"
      subtitle="One company, many projects: record purchases, expenses and sales as usual and pick this project on them.">
      <ProjectForm />
    </ProjectPage>
  )
}
