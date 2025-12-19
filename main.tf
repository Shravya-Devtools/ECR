# Provider block to assume a cross-account role in Account B from Account A
provider "aws" {
  region  = "us-east-1"
  
  # Assume Role to access resources in Account B from Account A
  assume_role {
    role_arn     = "arn:aws:iam::ACCOUNT_B_ID:role/TerraformRoleForAccountB"  # Replace with Account B's Role ARN
    session_name = "TerraformSession"
  }
}

# Create ECS Task Role in Account B (allows ECS to assume role to pull images from Account A's ECR)
resource "aws_iam_role" "ecs_task_role" {
  name               = "ecsTaskRole"
  assume_role_policy = jsonencode({
    "Version"   = "2012-10-17",
    "Statement" = [
      {
        "Effect"   = "Allow",
        "Principal" = {
          "Service" = "ecs-tasks.amazonaws.com"
        },
        "Action"   = "sts:AssumeRole"
      }
    ]
  })
}

# Create ECS Execution Role in Account B (grants ECS permissions to interact with AWS services like CloudWatch)
resource "aws_iam_role" "ecs_execution_role" {
  name               = "ecsExecutionRole"
  assume_role_policy = jsonencode({
    "Version"   = "2012-10-17",
    "Statement" = [
      {
        "Effect"   = "Allow",
        "Principal" = {
          "Service" = "ecs-tasks.amazonaws.com"
        },
        "Action"   = "sts:AssumeRole"
      }
    ]
  })
}

# Create ECS Task Definition using image from Account A's ECR repository
resource "aws_ecs_task_definition" "ecs_task" {
  family                   = "my-ecs-task-definition"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn
  container_definitions    = jsonencode([{
    name      = "my-container"
    image     = "741846357014.dkr.ecr.us-east-1.amazonaws.com/my-ecr-repository:v1.0.0"  # Replace with your ECR repository details
    memory    = 512
    cpu       = 256
    essential = true
  }])
  network_mode = "awsvpc"
}

# Create ECS Service in Account B to run the ECS Task
resource "aws_ecs_service" "ecs_service" {
  name            = "my-ecs-service"
  cluster         = "NewCluster"  # ECS cluster ID in Account B
  task_definition = aws_ecs_task_definition.ecs_task.arn
  desired_count   = 1
}

# Create Lambda function in Account B using an image from ECR in Account A
resource "aws_lambda_function" "my_lambda_function" {
  function_name = "my-lambda-function"
  role          = aws_iam_role.ecs_execution_role.arn
  image_uri     = "741846357014.dkr.ecr.us-east-1.amazonaws.com/my-ecr-repository:v1.0.0"
  package_type  = "Image"
}

# IAM Policy allowing ECS and Lambda to pull images from Account A's ECR
resource "aws_iam_policy" "ecr_access_policy" {
  name        = "ECRAccessPolicy"
  description = "Allow ECS and Lambda to pull images from Account A's ECR"
  policy      = jsonencode({
    "Version"   = "2012-10-17",
    "Statement" = [
      {
        "Effect"   = "Allow",
        "Action"   = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories"
        ],
        "Resource" = "arn:aws:ecr:us-east-1:741846357014:repository/my-ecr-repository"  # Replace with your ECR repository ARN
      }
    ]
  })
}

# Attach the ECR access policy to ECS and Lambda execution roles in Account B
resource "aws_iam_role_policy_attachment" "ecs_ecr_access" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecr_access_policy.arn
}

resource "aws_iam_role_policy_attachment" "lambda_ecr_access" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.ecr_access_policy.arn
}

# Output ECS Service and Lambda function names
output "ecs_service_name" {
  value = aws_ecs_service.ecs_service.name
}

output "lambda_function_name" {
  value = aws_lambda_function.my_lambda_function.function_name
}
